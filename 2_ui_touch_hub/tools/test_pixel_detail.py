"""Check font bit ordering, coverage arithmetic and fractional filter geometry."""
from datetime import datetime
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out = ROOT/'impl'/('pixel_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
    out.mkdir(exist_ok=False)
    font = json.loads((ROOT/'tools/ui_font_7x10.json').read_text())
    refs = []
    for ch, glyph in enumerate(font['glyphs']):
        for y, row in enumerate(glyph):
            for x, alpha in enumerate(row):
                refs.append(f'if(get_font_7x10({ch},{x},{y})!==2\'d{alpha}) $fatal(1,"Font bit order {ch}/{x}/{y}");')
    tb = '''`timescale 1ns/1ps
`include "font_7x10.vh"
`include "pixel_coverage.vh"
module tb_pixel_detail;
integer f,b,a,expected,frac,w,y,distance_value,cases=0;
reg clk=0,rst_n=0,power=1;
reg [13:0] x=868,py=150;
reg [1:0] mode=0;
reg [6:0] cutoff=64,resonance=0;
wire hit;
wire [23:0] rgb;
integer m,r,xx,cut,peak,delta,h,eq;
always #8 clk=~clk;
filter_panel_renderer dut(clk,rst_n,x,py,power,mode,cutoff,resonance,hit,rgb);
initial begin
FONT_CHECKS
    for(f=0;f<256;f=f+1)
        for(b=0;b<256;b=b+1)
            for(a=0;a<=4;a=a+1) begin
                expected=(a*f+(4-a)*b)/4;
                if(blend_channel_q4(f,b,a)!==expected[7:0]) $fatal(1,"Blend overflow");
                cases=cases+1;
            end
    for(w=3;w<=15;w=w+1)
        for(frac=0;frac<4;frac=frac+1)
            for(y=92;y<109;y=y+1) begin
                distance_value=(y*4>=400+frac) ? y*4-400-frac : 400+frac-y*4;
                expected=w+2-distance_value;
                if(expected<0)expected=0;
                if(expected>4)expected=4;
                if(curve_alpha_q4(y,400+frac,w)!==expected[2:0]) $fatal(1,"Coverage bound");
            end
    if(get_font_7x10(63,0,0)!==0 || get_font_7x10(1,7,0)!==0 ||
       get_font_7x10(1,0,10)!==0) $fatal(1,"Invalid glyph bounds");
    if(pack_font24("A9-+:.                  ")!=={6'd1,6'd36,6'd37,6'd38,6'd39,6'd40,108'd0})
        $fatal(1,"Constant string packing");
    for(f=0;f<16384;f=f+1)
        if(dut.div48(f[13:0])!==9'(f/48)) $fatal(1,"Bounded /48");
    for(f=0;f<32768;f=f+1)
        if(dut.div56(f[14:0])!==10'(f/56)) $fatal(1,"Bounded /56");
    for(f=0;f<8192;f=f+1)
        if(dut.div40(f[12:0])!==8'(f/40)) $fatal(1,"Bounded /40");
    repeat(4) @(negedge clk); rst_n=1;
    // All resonance values, all ramp columns and all four filter types.
    for(m=0;m<4;m=m+1) begin
        mode=m;
        for(r=0;r<128;r=r+1) begin
            resonance=r;h=r*44/128;peak=162-h;cut=898+64*280/128;
            for(xx=cut-66;xx<=cut+66;xx=xx+1) begin
                x=xx;repeat(4) @(negedge clk);delta=xx-cut;
                case(m)
                    0: if(delta< -48)eq=648;
                       else if(delta<=0)eq=648-(h*4*(48+delta))/48;
                       else if(delta<=64)eq=peak*4+((222-peak)*4*delta)/64;
                       else eq=888;
                    1: if(delta< -64)eq=888;
                       else if(delta<=0)eq=888-((222-peak)*4*(64+delta))/64;
                       else if(delta<=48)eq=peak*4+(h*4*delta)/48;
                       else eq=648;
                    2: if(delta< -56)eq=888;
                       else if(delta<=0)eq=888-((222-peak)*4*(56+delta))/56;
                       else if(delta<=56)eq=peak*4+((222-peak)*4*delta)/56;
                       else eq=888;
                    3: if(delta< -40)eq=648;
                       else if(delta<=0)eq=648+(h*4*(40+delta))/40;
                       else if(delta<=40)eq=(162+h)*4-(h*4*delta)/40;
                       else eq=648;
                endcase
                if(dut.s1_target_q2!==eq[15:0])
                    $fatal(1,"Filter Q2 mode=%0d res=%0d x=%0d actual=%0d expected=%0d",m,r,xx,dut.s1_target_q2,eq);
            end
        end
    end
    power=0;repeat(4) @(negedge clk);
    if(dut.s1_target_q2!==16'd648) $fatal(1,"Bypass geometry");
    $display("PASS: 2870 glyph pixels, %0d blend cases, coverage bounds, packed labels and 68096 fractional filter positions",cases);
    $finish;
end
endmodule
'''.replace('FONT_CHECKS','\n'.join(refs))
    (out/'tb_pixel_detail.v').write_text(tb)
    subprocess.run([str(MS/'vlib.exe'),'work'],cwd=out,check=True,capture_output=True)
    ui=ROOT/'rtl/ui_vector_engine'
    with (out/'compile.log').open('w') as log:
        subprocess.run([str(MS/'vlog.exe'),'-sv','+incdir+'+str(ui),
                        str(ui/'filter_panel_renderer.v'),'tb_pixel_detail.v'],
                       cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(MS/'vsim.exe'),'-c','-l','simulation.log','tb_pixel_detail',
                    '-do','run -all; quit -f'],cwd=out,capture_output=True,check=True)
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:
        raise RuntimeError(f'Pixel detail verification failed: {out}')
    print(next(line for line in log.splitlines() if 'PASS:' in line),flush=True)
    print(out,flush=True)


if __name__=='__main__':
    main()
