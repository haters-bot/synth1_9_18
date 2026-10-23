"""Exhaustively compare touch hit decoding with the committed RTL baseline."""
from datetime import datetime
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out=ROOT/'impl'/('router_region_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    reference=subprocess.check_output(
        ['git','show','542cdeb:rtl/touch_intake/touch_event_router.v'],cwd=ROOT).decode()
    reference=reference.replace('module touch_event_router (',
                                'module touch_event_router_reference (',1)
    (out/'reference.v').write_text(reference)
    ports=reference[reference.index('module touch_event_router_reference'):reference.index(');')]
    live={'clk','rst_n'}
    connections=[]
    for match in re.finditer(r'input\s+wire\s*(\[\d+:\d+\])?\s*([^\n]+)',ports):
        width,names=match.groups()
        for name in names.split('//')[0].rstrip(' ,\r').split(','):
            name=name.strip()
            if not name:continue
            if name in live:value=name
            elif width:
                msb,lsb=map(int,re.findall(r'\d+',width));value=f"{msb-lsb+1}'d0"
            else:value="1'b0"
            connections.append(f'.{name}({value})')
    def ports_for(prefix):
        return ',\n'.join(f'.{name}({prefix}_{name})' for name in [])
    tb='''`timescale 1ns/1ps
module tb_router_regions;
reg clk=0,rst_n=0;
reg [13:0] x=0,y=0;
integer xi,yi,checks=0;
always #8 clk=~clk;
touch_event_router dut(CONNECTIONS_NEW);
touch_event_router_reference refdut(CONNECTIONS_OLD);
initial begin
    repeat(4) @(negedge clk);rst_n=1;
    force dut.s0_tx=x;force dut.s0_ty=y;
    force refdut.s0_tx=x;force refdut.s0_ty=y;
    for(yi=0;yi<=680;yi=yi+1) for(xi=0;xi<1280;xi=xi+1) begin
        x=xi;y=yi;#1;
        if({dut.comb_is_knob,dut.comb_knob_id,dut.comb_is_btn,dut.comb_btn_id,dut.comb_btn_act} !==
           {refdut.comb_is_knob,refdut.comb_knob_id,refdut.comb_is_btn,refdut.comb_btn_id,refdut.comb_btn_act})
            $fatal(1,"Router region mismatch at %0d,%0d: %b/%h/%b/%h/%d != %b/%h/%b/%h/%d",xi,yi,
                dut.comb_is_knob,dut.comb_knob_id,dut.comb_is_btn,dut.comb_btn_id,dut.comb_btn_act,
                refdut.comb_is_knob,refdut.comb_knob_id,refdut.comb_is_btn,refdut.comb_btn_id,refdut.comb_btn_act);
        checks=checks+1;
    end
    $display("PASS: %0d exact raw UI coordinate classifications vs HEAD",checks);
    $finish;
end
endmodule
'''
    new_connections=[c for c in connections]
    # The test bench drives common sequential inputs directly; outputs are unused.
    for name in ['touch_valid','raw_touch_x','raw_touch_y','touch_state',
                 'curve_capture_active','curve_focus_valid','curve_focus_id']:
        new_connections=[c.replace(f'.{name}(',f'.{name}(') for c in new_connections]
    tb=tb.replace('CONNECTIONS_NEW',',\n'.join(new_connections))
    tb=tb.replace('CONNECTIONS_OLD',',\n'.join(new_connections))
    # Unconnected output ports are legal; unused input ports get constants.
    (out/'tb_router_regions.v').write_text(tb)
    def run(args,name):
        with (out/name).open('w') as log:
            subprocess.run([str(a) for a in args],cwd=out,stdout=log,
                           stderr=subprocess.STDOUT,check=True,timeout=600)
    run([MS/'vlib.exe','work'],'vlib.log')
    run([MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),
         ROOT/'rtl/touch_intake/touch_event_router.v',out/'reference.v',
         out/'tb_router_regions.v'],'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_router_regions',
         '-do','onerror {quit -code 1}; run -all; quit -f'],'vsim.log')
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:
        raise RuntimeError(f'Router equivalence failed: {out}')
    print(next(line for line in log.splitlines() if 'PASS:' in line));print(out)


if __name__=='__main__':main()
