`timescale 1ns/1ps
module tb_modulation_values;
 reg clk=0,rst_n=0;
 reg [146:0] nodes=0;
 reg [105:0] sources=0;
 reg [423:0] depths=0;
 reg [370:0] base_values=0;
 wire [370:0] preview_values;
 wire [12:0] raster_q6;
 integer wave,d,i,j,base,expected,checks=0;
 modulation_preview #(.PREVIEW_BASE_TICKS(100000)) dut(.clk(clk),.rst_n(rst_n),
  .nodes(nodes),.rates(9'd0),.stepped(3'd0),.active_tab(2'd0),.active_phase(9'd0),
  .raster_index(9'd0),.sources(sources),.depths(depths),.base_values(base_values),
  .preview_values(preview_values),.raster_q6(raster_q6));
 always #10 clk=~clk;
 task check_all;
  begin
   repeat(65)@(negedge clk);
   for(i=0;i<53;i=i+1)begin
    d=$signed(depths[i*8+:8]);base=base_values[i*7+:7];
    expected=sources[i*2+:2]==0 ? base : ((d<0 ? 127-wave : wave)*(d<0 ? -d : d))/127;
    if(preview_values[i*7+:7]!==expected[6:0])
     $fatal(1,"Preview mismatch wave=%0d depth=%0d target=%0d base=%0d expected=%0d got=%0d",wave,d,i,base,expected,preview_values[i*7+:7]);
    checks=checks+1;
   end
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  // Every wave value and every legal depth, packed into distinct scan slots.
  for(wave=0;wave<128;wave=wave+1)begin
   nodes={21{wave[6:0]}};
   repeat(600)@(negedge clk);
   for(j=0;j<5;j=j+1)begin
    for(i=0;i<53;i=i+1)begin
     depths[i*8+:8]=((j*53+i)%255)-127;
     sources[i*2+:2]=1+(i%3);base_values[i*7+:7]=(i*17+wave)%128;
    end
    check_all();
    // Changing only base must leave every bound preview unchanged.
    base_values=~base_values;check_all();
   end
  end
  sources=0;check_all();
  $display("PASS: %0d independent preview comparisons; all 128 wave values x 255 signed depths, three sources, 53 destinations, static-base isolation and unbound bypass",checks);
  $finish;
 end
 initial begin #10000000;$fatal(1,"Modulation values watchdog");end
endmodule
