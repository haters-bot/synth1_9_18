"""Compare knob pixels against the fixed pre-optimization 542cdeb renderer."""
from datetime import datetime
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out=ROOT/'impl'/('knob_pixel_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    reference=subprocess.check_output(
        ['git','show','542cdeb:rtl/ui_vector_engine/knob_vector_unit.v'],cwd=ROOT).decode()
    reference=reference.replace('module knob_vector_unit (',
                                'module knob_vector_unit_reference (',1)
    (out/'reference.v').write_text(reference)
    ports=reference[reference.index('module knob_vector_unit_reference'):reference.index(');')]
    connections=[]
    live={'clk','rst_n','in_x','in_y'}
    for match in re.finditer(r'input\s+wire\s*(\[\d+:\d+\])?\s*([^\n]+)',ports):
        width,names=match.groups()
        for name in names.split('//')[0].rstrip(' ,\r').split(','):
            name=name.strip()
            if not name:continue
            if name in live:value=name
            elif name.startswith('val_'):value='parameter_value'
            elif name=='selected_param_id':value='selected_id'
            elif width:
                msb,lsb=map(int,re.findall(r'\d+',width));value=f"{msb-lsb+1}'d0"
            else:value="1'b0"
            connections.append(f'.{name}({value})')
    inputs=[item for item in connections if not item.startswith('.out_')]
    outputs=['.out_hit_knob(new_hit)','.out_knob_rgb(new_rgb)']
    ref_outputs=['.out_hit_knob(old_hit)','.out_knob_rgb(old_rgb)']
    tb='''`timescale 1ns/1ps
module tb_knob_pixels;
reg clk=0,rst_n=0;
reg [13:0] in_x=0,in_y=0;
wire new_hit,old_hit;
wire [23:0] new_rgb,old_rgb;
reg old_hit_delayed=0;
reg [23:0] old_rgb_delayed=0;
reg [6:0] parameter_value=0;
reg [7:0] selected_id=0;
integer x,y,scenario,checks=0,warmup=0;
always #8 clk=~clk;
always @(posedge clk) begin old_hit_delayed<=old_hit;old_rgb_delayed<=old_rgb;end
knob_vector_unit dut(CONNECTIONS_NEW);
knob_vector_unit_reference refdut(CONNECTIONS_OLD);
always @(negedge clk) if(rst_n) begin
    #1;
    warmup=warmup+1;
    if(warmup>8) begin
        if({new_hit,new_rgb}!=={old_hit_delayed,old_rgb_delayed})
            $fatal(1,"Knob raster mismatch at %0d,%0d: %b/%h != %b/%h",x,y,new_hit,new_rgb,old_hit_delayed,old_rgb_delayed);
        checks=checks+1;
    end
end
initial begin
    repeat(5) @(negedge clk);rst_n=1;
    repeat(12) @(negedge clk);
    for(scenario=0;scenario<4;scenario=scenario+1) begin
        case(scenario) 0:parameter_value=0;1:parameter_value=63;2:parameter_value=100;3:parameter_value=127;endcase
    for(y=0;y<720;y=y+1) for(x=0;x<1280;x=x+1) begin
        in_x=x;in_y=y;selected_id=(x+y)%64;@(negedge clk);
    end
    end
    repeat(4) @(negedge clk);
    if(checks<3686400) $fatal(1,"Incomplete raster checks: %0d",checks);
    $display("PASS: %0d exact hit/RGB pixel comparisons across four full 1280x720 frames",checks);
    $finish;
end
endmodule
'''.replace('CONNECTIONS_NEW',',\n'.join(inputs+outputs))
    tb=tb.replace('CONNECTIONS_OLD',',\n'.join(inputs+ref_outputs))
    (out/'tb_knob_pixels.v').write_text(tb)
    def run(args,name):
        with (out/name).open('w') as log:
            subprocess.run([str(a) for a in args],cwd=out,stdout=log,
                           stderr=subprocess.STDOUT,check=True,timeout=600)
    ui=ROOT/'rtl/ui_vector_engine'
    run([MS/'vlib.exe','work'],'vlib.log')
    run([MS/'vlog.exe','-sv','+incdir+'+str(ui),ui/'knob_vector_unit.v',
         out/'reference.v',out/'tb_knob_pixels.v'],'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_knob_pixels',
         '-do','onerror {quit -code 1}; run -all; quit -f'],'vsim.log')
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:
        raise RuntimeError(f'Knob raster check failed: {out}')
    print(next(line for line in log.splitlines() if 'PASS:' in line));print(out)


if __name__=='__main__':main()

