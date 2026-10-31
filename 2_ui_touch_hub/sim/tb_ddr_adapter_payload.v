`timescale 1ns/1ps
// Exercise the production adapter with request payload changing after acceptance.
// Independent command/data stalls must retain the accepted address/data/mask.
module tb_ddr_adapter_payload;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,init_done=0,req_valid=0,req_write=0;
 reg [28:0] req_addr=0;
 reg [255:0] req_wdata=0;
 reg [31:0] req_wmask=0;
 wire req_ready,rsp_valid,rsp_write,rsp_error;
 wire [255:0] rsp_rdata;
 reg mc_cmd_ready=0,mc_wr_data_rdy=0,mc_rd_data_valid=0,mc_rd_data_end=0;
 reg [255:0] mc_rd_data=0;
 wire [2:0] mc_cmd;
 wire mc_cmd_en,mc_wr_data_en,mc_wr_data_end;
 wire [28:0] mc_addr;
 wire [255:0] mc_wr_data;
 wire [31:0] mc_wr_data_mask;
 ddr3_user_port_adapter dut(.*);
 task tick;begin @(negedge clk);end endtask
 integer commands=0,writes=0,replies=0;
 reg [28:0] expected_addr;
 reg [255:0] expected_data;
 reg [31:0] expected_mask;
 reg expected_write;
 always @(posedge clk)if(rst_n)begin
  if(mc_cmd_en)begin
   if(mc_addr!==expected_addr || mc_cmd!==(expected_write ? 3'd0 : 3'd1))
    $fatal(1,"Command payload changed while pending");
   if(mc_cmd_ready)commands=commands+1;
  end
  if(mc_wr_data_en)begin
   if(!expected_write || !mc_wr_data_end || mc_wr_data!==expected_data || mc_wr_data_mask!==expected_mask)
    $fatal(1,"Write payload changed while pending");
   if(mc_wr_data_rdy)writes=writes+1;
  end
  if(rsp_valid)replies=replies+1;
 end
 task change_inputs;
 begin
  req_valid=0;req_write=~req_write;req_addr=req_addr+29'd128;
  req_wdata=~req_wdata;req_wmask=~req_wmask;
 end endtask
 task accept;
 input wr;input integer index;
 begin
  if(!req_ready)$fatal(1,"Adapter not ready before transaction");
  expected_write=wr;expected_addr=index*8;
  expected_data={8{32'h12345678+index}};expected_mask=32'hf0f00000+index;
  req_write=wr;req_addr=expected_addr;req_wdata=expected_data;req_wmask=expected_mask;
  req_valid=1;tick;
  if(req_ready || !mc_cmd_en || mc_wr_data_en!==wr)$fatal(1,"Acceptance cycle changed");
  change_inputs;
 end endtask
 task await_write_reply;
 begin
  // Existing adapter posts write response on the final downstream handshake.
  if(!rsp_valid || !rsp_write || rsp_error || !req_ready)$fatal(1,"Write completion mismatch");
  tick;
  if(rsp_valid || mc_cmd_en || mc_wr_data_en)$fatal(1,"Duplicate completion/command");
 end endtask
 integer i,c0,w0,r0;
 initial begin
  repeat(3)tick;rst_n=1;tick;
  // Uncalibrated or valid-low payload changes must not issue commands.
  repeat(4)begin change_inputs;req_valid=1;tick;if(req_ready || mc_cmd_en || mc_wr_data_en)$fatal(1,"Uninitialized request accepted");end
  req_valid=0;init_done=1;repeat(3)begin change_inputs;tick;if(!req_ready || mc_cmd_en || mc_wr_data_en)$fatal(1,"Idle payload created transaction");end
  for(i=0;i<3;i=i+1)begin
   c0=commands;w0=writes;r0=replies;
   accept(1,i+1);
   repeat(7)begin change_inputs;tick;if(req_ready || rsp_valid)$fatal(1,"Stalled transaction completed");end
   if(i==0)begin
    mc_cmd_ready=1;tick;mc_cmd_ready=0;
    if(mc_cmd_en || !mc_wr_data_en || rsp_valid)$fatal(1,"Command-first ordering");
    repeat(4)begin change_inputs;tick;end
    mc_wr_data_rdy=1;tick;mc_wr_data_rdy=0;
   end else if(i==1)begin
    mc_wr_data_rdy=1;tick;mc_wr_data_rdy=0;
    if(!mc_cmd_en || mc_wr_data_en || rsp_valid)$fatal(1,"Data-first ordering");
    repeat(4)begin change_inputs;tick;end
    mc_cmd_ready=1;tick;mc_cmd_ready=0;
   end else begin mc_cmd_ready=1;mc_wr_data_rdy=1;tick;mc_cmd_ready=0;mc_wr_data_rdy=0;end
   await_write_reply;
   if(commands!=c0+1 || writes!=w0+1 || replies!=r0+1)$fatal(1,"Missing/duplicate write transaction");
  end
  for(i=0;i<2;i=i+1)begin
   c0=commands;w0=writes;r0=replies;
   accept(0,i+10);
   repeat(5)begin change_inputs;tick;end
   mc_cmd_ready=1;tick;mc_cmd_ready=0;
   repeat(5)begin change_inputs;tick;if(req_ready || rsp_valid)$fatal(1,"Read completed before response");end
   mc_rd_data={8{32'hcafef00d+i}};mc_rd_data_end=(i==0);mc_rd_data_valid=1;tick;mc_rd_data_valid=0;
   if(!rsp_valid || rsp_write || rsp_error!==(i!=0) || rsp_rdata!==mc_rd_data || !req_ready)
    $fatal(1,"Read response/end flag mismatch");
   tick;
   if(rsp_valid || commands!=c0+1 || writes!=w0 || replies!=r0+1)$fatal(1,"Missing/duplicate read transaction");
  end
  // Reset while both downstream channels are stalled cancels the command.
  accept(1,20);repeat(3)tick;rst_n=0;tick;
  if(mc_cmd_en || mc_wr_data_en || rsp_valid)$fatal(1,"Reset did not cancel pending request");
  rst_n=1;req_valid=0;tick;
  if(!req_ready)$fatal(1,"Adapter not reusable after reset");
  $display("PASS: production DDR adapter idle sampling, payload hold, command/data order, reads/errors and reset");
  $finish;
 end
 initial begin #200000;$fatal(1,"Timeout");end
endmodule
