"""Compare button pixels against the fixed pre-optimization 542cdeb renderer."""
from datetime import datetime
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out=ROOT/'impl'/('button_pixel_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    reference=subprocess.check_output(
        ['git','show','542cdeb:rtl/ui_vector_engine/button_vector_unit.v'],cwd=ROOT).decode()
    reference=reference.replace('module button_vector_unit (',
                                'module button_vector_unit_reference (',1)
    (out/'reference.v').write_text(reference)
    ports=reference[reference.index('module button_vector_unit_reference'):reference.index(');')]
    connections=[]
    live={'clk','rst_n','in_x','in_y'}
    for match in re.finditer(r'input\s+wire\s*(\[\d+:\d+\])?\s*([^\n]+)',ports):
        width,names=match.groups()
        for name in names.split('//')[0].rstrip(' ,\r').split(','):
            name=name.strip()
            if not name:continue
            if name in live:value=name
            elif width:
                msb,lsb=map(int,re.findall(r'\d+',width))
                offset=sum(map(ord,name))%16
                value=f"test_state[{offset}+:{msb-lsb+1}]"
            else:value=f"test_state[{sum(map(ord,name))%32}]"
            connections.append(f'.{name}({value})')
    inputs=[item for item in connections if not item.startswith('.out_')]
    outputs=['.out_hit_btn(new_hit)','.out_btn_rgb(new_rgb)']
    ref_outputs=['.out_hit_btn(old_hit)','.out_btn_rgb(old_rgb)']
    tb='''`timescale 1ns/1ps
module tb_button_pixels;
reg clk=0,rst_n=0;
reg [13:0] in_x=0,in_y=0;
wire new_hit,old_hit;
wire [23:0] new_rgb,old_rgb;
reg [31:0] test_state=0;
integer x,y,scenario,checks=0;
always #8 clk=~clk;
button_vector_unit dut(CONNECTIONS_NEW);
button_vector_unit_reference refdut(CONNECTIONS_OLD);
always @(negedge clk) if(rst_n) begin
    #1;
    if({new_hit,new_rgb}!=={old_hit,old_rgb})
        $fatal(1,"Button raster mismatch at %0d,%0d: %b/%h != %b/%h",x,y,new_hit,new_rgb,old_hit,old_rgb);
    checks=checks+1;
end
initial begin
    repeat(5) @(negedge clk);rst_n=1;
    for(scenario=0;scenario<4;scenario=scenario+1) begin
        case(scenario)
            0:test_state=0;1:test_state=32'hFFFFFFFF;
            2:test_state=32'h12345678;3:test_state=32'hA5C3E10F;
        endcase
        for(y=0;y<720;y=y+1) for(x=0;x<1280;x=x+1) begin
            in_x=x;in_y=y;@(negedge clk);
        end
    end
    repeat(4) @(negedge clk);
    if(checks<3686400) $fatal(1,"Incomplete raster checks: %0d",checks);
    $display("PASS: %0d exact hit/RGB pixel comparisons across four button state frames",checks);
    $finish;
end
endmodule
'''.replace('CONNECTIONS_NEW',',\n'.join(inputs+outputs))
    tb=tb.replace('CONNECTIONS_OLD',',\n'.join(inputs+ref_outputs))
    (out/'tb_button_pixels.v').write_text(tb)
    def run(args,name):
        with (out/name).open('w') as log:
            subprocess.run([str(a) for a in args],cwd=out,stdout=log,
                           stderr=subprocess.STDOUT,check=True,timeout=600)
    ui=ROOT/'rtl/ui_vector_engine'
    run([MS/'vlib.exe','work'],'vlib.log')
    run([MS/'vlog.exe','-sv','+incdir+'+str(ui),ui/'button_vector_unit.v',
         out/'reference.v',out/'tb_button_pixels.v'],'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_button_pixels',
         '-do','onerror {quit -code 1}; run -all; quit -f'],'vsim.log')
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:
        raise RuntimeError(f'Button raster check failed: {out}')
    print(next(line for line in log.splitlines() if 'PASS:' in line));print(out)


if __name__=='__main__':main()
