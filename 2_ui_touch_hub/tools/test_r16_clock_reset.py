"""Compare LFO output pixels with the preserved candidate and check PHY reset.

The reset test uses Gowin's actual GW5A OSER10 simulation primitive; exercises
off-edge assertion/deassertion, stopped FCLK and repeated lock/reset loss.
"""
from datetime import datetime
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')
PRIM=Path('D:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/simlib/gw5a/prim_sim.v')

def main():
    out=ROOT/'impl'/('clock_reset_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    old=(ROOT/'impl/R16A_build_20261019_135450/rtl/ui_vector_engine/lfo_panel_renderer.v').read_text()
    (out/'lfo_reference.v').write_text(old.replace('module lfo_panel_renderer(', 'module lfo_reference('))
    old_hint=(ROOT/'impl/R16A_build_20261019_135450/rtl/ui_vector_engine/curve_hint_renderer.v').read_text()
    (out/'hint_reference.v').write_text(old_hint.replace('module curve_hint_renderer(', 'module hint_reference('))
    tb=r'''`timescale 1ns/1ps
module tb_clock_reset;
reg clk=0,rst_n=0;
always #10 clk=~clk;
reg [13:0] x=0,y=0;
reg [1:0] tab=0,preset=0;
reg [48:0] nodes=49'h123456789AB;
reg [2:0] rate=0;
reg once_mode=0,stepped=0,running=0;
reg [8:0] phase=0;
reg [12:0] curve=0;
wire hit,ref_hit;
wire [23:0] rgb,ref_rgb;
lfo_panel_renderer dut(clk,rst_n,x,y,tab,preset,nodes,rate,once_mode,stepped,phase,running,curve,hit,rgb);
lfo_reference ref_dut(clk,rst_n,x,y,tab,preset,nodes,rate,once_mode,stepped,phase,running,curve,ref_hit,ref_rgb);
wire hint_hit,ref_hint_hit;
wire [23:0] hint_rgb,ref_hint_rgb;
curve_hint_renderer hint(clk,rst_n,x,y,tab,hint_hit,hint_rgb);
hint_reference ref_hint(clk,rst_n,x,y,tab,ref_hint_hit,ref_hint_rgb);
integer xx,yy,s,checks=0,age=0;
reg pixel_done=0,reset_done=0;
always @(posedge clk) begin
    #1;
    if(rst_n) begin
        age=age+1;
        if(age>8) begin
            if({hit,rgb} !== {ref_hit,ref_rgb})
                $fatal(1,"LFO pixel differs at delayed x=%d y=%d state=%d actual=%h expected=%h",x,y,s,rgb,ref_rgb);
            if({hint_hit,hint_rgb} !== {ref_hint_hit,ref_hint_rgb})
                $fatal(1,"Hint pixel differs at delayed x=%d y=%d state=%d actual=%h expected=%h",x,y,s,hint_rgb,ref_hint_rgb);
            checks=checks+1;
        end
    end
end
initial begin
    repeat(5) @(negedge clk);rst_n=1;
    for(s=0;s<12;s=s+1) begin
        tab=s%3;preset=(s/3)%3;rate=s%6;once_mode=s%2;
        stepped=(s/2)%2;running=(s/4)%2;nodes={$random,$random};
        for(yy=366;yy<695;yy=yy+1)
            for(xx=790;xx<1260;xx=xx+1) begin
                @(negedge clk);x=xx;y=yy;phase=xx%385;curve=(xx*37)%8129;
            end
    end
    for(s=0;s<3;s=s+1) begin
        tab=s;
        for(yy=100;yy<630;yy=yy+1)
            if(yy<122 || yy>=588)
                for(xx=0;xx<1280;xx=xx+1)begin
                    @(negedge clk);x=xx;y=yy;
                end
    end
    repeat(10) @(negedge clk);pixel_done=1;
end

reg fclk=0,clock_enable=1,phy_rst=1,gsr=0;
always #2 if(clock_enable) fclk=~fclk;
GSR GSR(gsr);
wire [1:0] lane;
reg [9:0] data=10'b1010110010;
dvi_tx_tmds_phy phy(clk,fclk,phy_rst,data,lane);
integer n,edges,reset_checks=0;
task release_reset;
    input integer offset;
    begin
        #offset;phy_rst=0;
        for(edges=0;edges<3;edges=edges+1) begin
            @(posedge fclk);#0.01;
            if(phy.reset_pipe[2] !== (edges<2)) $fatal(1,"Early/late FCLK reset release");
            reset_checks=reset_checks+1;
        end
        repeat(24) @(negedge fclk);
        if((^lane)===1'bx) $fatal(1,"Unknown serial output after reset");
        reset_checks=reset_checks+1;
    end
endtask
initial begin
    #13;gsr=1;
    for(n=1;n<=20;n=n+1) begin
        #1.17;phy_rst=1;#0.01;
        if(phy.reset_pipe !== 3'b111) $fatal(1,"Reset assertion waits for clock");
        release_reset(n%7+1);
    end
    @(negedge fclk);clock_enable=0;
    #1.3;phy_rst=1;#0.01;
    if(phy.reset_pipe !== 3'b111) $fatal(1,"Reset fails with stopped FCLK");
    #5;phy_rst=0;#30;
    if(phy.reset_pipe !== 3'b111) $fatal(1,"Reset releases with stopped FCLK");
    clock_enable=1;
    repeat(4) @(posedge fclk);#0.01;
    if(phy.reset_pipe[2]!==0) $fatal(1,"Reset fails to release after clock returns");
    reset_done=1;
end
initial begin
    wait(pixel_done && reset_done);
    if(checks<2100000 || reset_checks!=80) $fatal(1,"Incomplete verification coverage");
    $display("PASS: %0d exact LFO/hint output pixels across 12 control states and all hint rows/tabs; %0d primitive reset checks, stopped FCLK and 20 repeated off-edge resets",checks,reset_checks);
    $finish;
end
initial begin #100000000; $fatal(1,"Timeout"); end
endmodule
'''
    (out/'tb_clock_reset.v').write_text(tb)
    subprocess.run([str(MS/'vlib.exe'),'work'],cwd=out,check=True,capture_output=True)
    ui=ROOT/'rtl/ui_vector_engine'
    with (out/'compile.log').open('w') as log:
        subprocess.run([str(MS/'vlog.exe'),'-sv','+incdir+'+str(ui),str(PRIM),
                        str(ROOT/'rtl/dvi_tx/dvi_tx_tmds_phy.v'),str(ui/'lfo_panel_renderer.v'),
                        str(ui/'curve_hint_renderer.v'),'lfo_reference.v','hint_reference.v',
                        'tb_clock_reset.v'],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(MS/'vsim.exe'),'-c','-l','simulation.log','tb_clock_reset',
                    '-do','run -all; quit -f'],cwd=out,capture_output=True,check=True)
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:
        raise RuntimeError(f'Clock/reset verification failed: {out}')
    print(next(line for line in log.splitlines() if 'PASS:' in line),flush=True)
    print(out,flush=True)

if __name__=='__main__':main()
