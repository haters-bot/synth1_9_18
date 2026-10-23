"""Exercise page changes through actual renderer inputs and render page artifacts."""
from datetime import datetime
from pathlib import Path
import re,subprocess,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')
def main():
 out=ROOT/'impl'/('navigation_'+datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir()
 ports=(ROOT/'rtl/ui_vector_engine/ui_top_renderer.v').read_text().split('module ui_top_renderer',1)[1].split(');',1)[0]
 live={'clk','rst_n','in_hsync','in_vsync','in_den','in_pixel_x','in_pixel_y','ui_touch_valid','ui_touch_down','ui_touch_x','ui_touch_y'}
 connect=[]
 for m in re.finditer(r'input\s+wire\s*(\[\d+:\d+\])?\s*([^\n]+)',ports):
  width,names=m.groups();bits=1 if not width else int(width[1:].split(':')[0])+1
  for name in names.split('//')[0].rstrip(' ,\r').split(','):
   name=name.strip()
   if not name:continue
   value=name if name in live else {'val_macro1':'m1','val_macro2':'m2','val_macro3':'m3','val_macro4':'m4'}.get(name,f"{bits}'d{100 if name=='val_master_vol' else 64 if name.startswith('val_') and bits==7 else 1 if name in ['val_osca_power','val_oscb_power','val_flt_power','usb_connected'] else 0}")
   connect.append(f'.{name}({value})')
 connect+=['.out_pixel_data(rgb)','.out_den(den)','.out_hsync(hs)','.out_vsync(vs)',
           '.navigation_capture(capture)','.navigation_delta_valid(dv)','.navigation_delta_id(did)','.navigation_delta_value(delta)']
 tb=r'''`timescale 1ns/1ps
module tb_navigation;
reg clk=0,rst_n=0,in_hsync=0,in_vsync=0,in_den=1;
reg [13:0] in_pixel_x=0,in_pixel_y=0,ui_touch_x=0,ui_touch_y=0;
reg ui_touch_valid=0,ui_touch_down=0;
wire [23:0] rgb;wire den,hs,vs,capture,dv;wire [7:0] did;wire signed [7:0] delta;
wire [6:0] m1,m2,m3,m4;
reg [6:0] initial_m1,initial_m2,initial_m4;
integer file,x,y,i,delta_count=0;reg [146:0] nodes_saved;reg [105:0] routes_saved;
reg [132:0] fx_saved;reg [8:0] phase_saved;
reg [7:0] last_id;reg signed [7:0] last_delta;
reg scan_check=0;integer count=0,k,j;
reg [23:0] expected,history[0:6];
always #10 clk=~clk;
always @(posedge clk)if(dv)begin delta_count=delta_count+1;last_id=did;last_delta=delta;end
always @(posedge clk)if(scan_check)begin
 for(j=6;j>0;j=j-1)history[j]=history[j-1];history[0]=expected;count=count+1;
 #1;if(count>10 && rgb!==history[6])begin $display("Mismatch count=%0d view=%0d section=%0d x=%0d y=%0d rgb=%h expected=%h",count,dut.navigation_view,dut.settings_section_id,in_pixel_x,in_pixel_y,rgb,history[6]);$fatal(1,"Navigation pixel latency differs from seven clocks");end
end
ui_top_renderer dut(CONNECTIONS);
param_merger bank(.clk(clk),.rst_n(rst_n),.spi_param_valid(1'b0),.spi_param_id(8'd0),.spi_param_val(7'd0),
 .touch_delta_valid(dv),.touch_selected_id(did),.touch_delta_val(delta),
 .curve_update_valid(1'b0),.curve_update_filter(1'b0),.curve_update_tab(2'd0),.curve_update_mask(5'd0),
 .curve_update_values(35'd0),.midi_tx_busy(1'b0),.btn_tap_valid(1'b0),.btn_tap_id(8'd0),.btn_tap_action(2'd0),
 .val_macro1(m1),.val_macro2(m2),.val_macro3(m3),.val_macro4(m4));
task packet;
 input integer px,py;input down;
 begin @(negedge clk);ui_touch_valid=1;ui_touch_down=down;ui_touch_x=px;ui_touch_y=py;
 @(negedge clk);ui_touch_valid=0;repeat(12)@(negedge clk);end
endtask
task click;input integer px,py;
 begin packet(px,py,1);packet(0,0,0);end
endtask
task frame_boundary;
 begin @(negedge clk);in_vsync=1;repeat(8)@(negedge clk);in_vsync=0;repeat(12)@(negedge clk);end
endtask
task scan_page;
 input integer which;
 begin count=0;scan_check=1;
 for(k=0;k<400;k=k+1)begin
  @(negedge clk);
  case(k%4)
   0:begin in_pixel_x=0;in_pixel_y=100;expected=which==2 ? 24'h1A2735 : 24'h101318;end
   1:begin in_pixel_x=which==1 ? 24 : which==2 ? 40 : 48;in_pixel_y=which==1 ? 96 : which==2 ? 130 : 200;
      expected=which==1 ? 24'h35495F : which==2 ? 24'h142030 : 24'h17283B;end
   2:begin in_pixel_x=0;in_pixel_y=0;expected=24'h151D29;end
   3:begin in_pixel_x=0;in_pixel_y=700;expected=24'h101318;end
  endcase
 end
 @(negedge clk);scan_check=0;end
endtask
task scan_settings_tab;
 input integer selected;
 begin count=0;scan_check=1;
 for(k=0;k<400;k=k+1)begin
  @(negedge clk);
  case(k%5)
   0:begin in_pixel_x=300;in_pixel_y=110;expected=selected==1?24'h285064:24'h1A2735;end
   1:begin in_pixel_x=600;in_pixel_y=110;expected=selected==2?24'h285064:24'h1A2735;end
   2:begin in_pixel_x=900;in_pixel_y=110;expected=selected==3?24'h285064:24'h1A2735;end
   3:begin in_pixel_x=1200;in_pixel_y=110;expected=selected==4?24'h285064:24'h1A2735;end
   4:begin in_pixel_x=0;in_pixel_y=100;expected=24'h1A2735;end
  endcase
 end
 @(negedge clk);scan_check=0;end
endtask
task screen;
 input [255:0] filename;
 begin file=$fopen(filename,"w");
 for(y=0;y<720;y=y+1)begin
  @(negedge clk);in_pixel_x=0;in_pixel_y=y;
  repeat(9)@(negedge clk);
  for(x=0;x<1280;x=x+1)begin
   @(negedge clk);in_pixel_x=x+7<1280 ? x+7 : 1279;
   $fwrite(file,"%06h\n",rgb);
   if((^rgb)===1'bx)$fatal(1,"Unknown navigation pixel");
  end
 end
 $fclose(file);end
endtask
initial begin
 repeat(8)@(negedge clk);rst_n=1;repeat(20)@(negedge clk);
 // Establish a real curve edit and route before navigation.
 click(960,460);click(1140,385);click(1030,268);
 nodes_saved=dut.lfo_all_nodes;routes_saved=dut.mod_sources;fx_saved=dut.fx_values;
 if(routes_saved[48+:2]!=1)$fatal(1,"Initial binding failed");
 // Click visual tab, but page must wait for vblank.
 click(440,22);
 if(dut.navigation_view!=0 || !capture)$fatal(1,"Page changed mid-frame or pending page did not block touch");
 frame_boundary();if(dut.navigation_view!=1)$fatal(1,"Visual page not committed");
 scan_page(1);
 for(i=0;i<20;i=i+1)begin
  click(960,420+i);click(448,416);click(1140,385);
 end
 if(dut.lfo_all_nodes!==nodes_saved || dut.mod_sources!==routes_saved || dut.fx_values!==fx_saved)
  $fatal(1,"Background synth changed on visualization page");
 click(650,22);frame_boundary();if(dut.navigation_view!=2)$fatal(1,"System page failed");
 scan_page(2);
 initial_m1=m1;initial_m2=m2;initial_m4=m4;
 click(264,256);click(600,320);click(600,448);
 if(delta_count!=3 || last_id!=4 || last_delta!=1)$fatal(1,"Macro event pairing/count failed");
 if(m1!=initial_m1-1 || m2!=initial_m2+1 || m4!=initial_m4+1)$fatal(1,"Macro changes did not reach real parameter bank");
 click(1000,548);if(!dut.show_diagnostics)$fatal(1,"Diagnostics toggle failed");
 click(450,100);if(dut.settings_section_id!=2)$fatal(1,"Display settings tab failed");scan_settings_tab(2);
 click(780,100);if(dut.settings_section_id!=3)$fatal(1,"Input settings tab failed");scan_settings_tab(3);
 click(1080,100);if(dut.settings_section_id!=4)$fatal(1,"About settings tab failed");scan_settings_tab(4);
 click(180,100);if(dut.settings_section_id!=1)$fatal(1,"Controls settings tab failed");scan_settings_tab(1);
 if(m1!=initial_m1-1 || m2!=initial_m2+1 || m4!=initial_m4+1)$fatal(1,"Changing settings tabs changed Macro values");
 click(48,22);frame_boundary();if(dut.navigation_view!=3)$fatal(1,"Menu did not open");
 scan_page(3);
 click(120,220);frame_boundary();if(dut.navigation_view!=0 || capture)$fatal(1,"Synth return blocked");
 if(dut.lfo_all_nodes!==nodes_saved || dut.mod_sources!==routes_saved || dut.fx_values!==fx_saved)
  $fatal(1,"Page return lost synth state");
 // Leaving synth during armed/drag mode cancels only transient capture.
 click(1140,385);packet(980,480,1);
 if(!dut.mod_dragging)$fatal(1,"Expected active drag");
 packet(440,22,1);packet(0,0,0);frame_boundary();
 if(dut.mod_armed || dut.mod_dragging || dut.mod_sources!==routes_saved)
  $fatal(1,"Navigation failed to cancel transient drag without losing routes");
 click(152,22);frame_boundary();click(448,416); // no stranded page/gesture capture
 if(capture)$fatal(1,"Navigation contact remained captured");
 $display("PASS: vblank page commit, six-slot visual isolation, real edit/binding retention, menu navigation, macro event pairing, diagnostics and cancel active BIND");
 $finish;
end
initial begin #150000000;$fatal(1,"Navigation timeout");end
endmodule
'''.replace('CONNECTIONS',',\n'.join(connect))
 (out/'tb_navigation.v').write_text(tb)
 def run(args,name,timeout=240):
  with (out/name).open('w') as f:subprocess.run([str(a) for a in args],cwd=out,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=timeout)
 run([MS/'vlib.exe','work'],'vlib.log')
 files=[ROOT/e.attrib['path'] for e in ET.parse(ROOT/'2_ui_touch_hub.gprj').findall('.//File') if e.attrib['path'].endswith('.v')]
 run([MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*files,'tb_navigation.v'],'compile.log')
 run([MS/'vsim.exe','-c','-l','simulation.log','tb_navigation','-do','onerror {quit -code 1}; run -all; quit -f'],'vsim.log',900)
 log=(out/'simulation.log').read_text(errors='replace')
 if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:raise RuntimeError(str(out))
 print(next(line for line in log.splitlines() if 'PASS:' in line));print(out,flush=True)
if __name__=='__main__':main()
