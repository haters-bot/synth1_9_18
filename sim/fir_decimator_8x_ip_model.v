// Simulation-only mathematical FIR/8 model using the project's coefficient file.
// This is not the encrypted vendor IP's cycle-accurate implementation. It lets
// full-top routing tests exercise nonzero audio and compare unchanged pipelines.
module fir_decimator_8x_ip(
 input wire clk,rstn,fir_valid_i,fir_sync_i,
 input wire signed [15:0] fir_data_i,
 output wire fir_rfi_o,
 output reg fir_valid_o,fir_sync_o,
 output reg signed [32:0] fir_data_o
);
 reg signed [17:0] coeff[0:127];
 reg signed [15:0] history[0:126];
 reg [2:0] phase;
 reg signed [63:0] accumulator;
 integer fd,read_ok,value,k;
 initial begin
  fd=$fopen("coeff_q17.txt","r");
  if(!fd)$fatal(1,"Missing simulation FIR coefficient file");
  for(k=0;k<128;k=k+1)begin
   read_ok=$fscanf(fd,"%d",value);
   if(read_ok!=1)$fatal(1,"Missing FIR coefficient %0d",k);
   coeff[k]=value;
  end
  $fclose(fd);
 end
 assign fir_rfi_o=1'b1;
 always @(posedge clk or negedge rstn)begin
  if(!rstn)begin
   phase<=0;fir_valid_o<=0;fir_sync_o<=0;fir_data_o<=0;
   for(k=0;k<127;k=k+1)history[k]<=0;
  end else begin
   fir_valid_o<=0;fir_sync_o<=0;
   if(fir_valid_i)begin
    phase<=phase+1'b1;
    for(k=126;k>0;k=k-1)history[k]<=history[k-1];
    history[0]<=fir_data_i;
    if(phase==7)begin
     accumulator=$signed(fir_data_i)*$signed(coeff[0]);
     for(k=1;k<128;k=k+1)
      accumulator=accumulator+$signed(history[k-1])*$signed(coeff[k]);
     fir_data_o<=accumulator[32:0];fir_valid_o<=1;fir_sync_o<=1;
    end
   end
  end
 end
endmodule
