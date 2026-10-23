"""Exercise real LFO bindings and compare scopes to independently computed values.

The separate reference scopes receive arithmetic from the test, not DUT preview
outputs. Pixel comparisons catch a scope still wired to the unmodulated bank.
"""
from datetime import datetime
from pathlib import Path
import argparse
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--renderer-ref',help='Git ref of old renderer; require reproduction of disconnected preview')
    args=parser.parse_args()
    out=ROOT/'impl'/('modulated_scopes_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    source=(ROOT/'rtl/ui_vector_engine/ui_top_renderer.v').read_text()
    ports=source[source.index('module ui_top_renderer'):source.index(');')]
    live={'clk','rst_n','ui_touch_valid','ui_touch_down','ui_touch_x','ui_touch_y','in_pixel_x','in_pixel_y'}
    bases={'val_osca_wt_pos':20,'val_oscb_wt_pos':30,'val_flt_cutoff':50,'val_flt_res':20,
           'val_env_attack':10,'val_env_hold':10,'val_env_decay':30,'val_env_sustain':40,'val_env_release':30}
    connections=[]
    for m in re.finditer(r'input\s+wire\s*(\[\d+:\d+\])?\s*([^\n]+)',ports):
        width,names=m.groups()
        for name in names.split('//')[0].rstrip(' ,\r').split(','):
            name=name.strip()
            if not name:continue
            bits=1 if not width else int(width[1:].split(':')[0])+1
            value=name if name in live else f"{bits}'d{bases.get(name,1 if name.endswith('power') or name=='in_den' else 0)}"
            connections.append(f'.{name}({value})')
    connections += ['.out_pixel_data(rgb)']
    tb=r'''`timescale 1ns/1ps
module tb_modulated_scopes;
reg clk=0,rst_n=0,ui_touch_valid=0,ui_touch_down=0;
reg [13:0] ui_touch_x=0,ui_touch_y=0,in_pixel_x=0,in_pixel_y=0;
wire [23:0] rgb;
reg [13:0] rx=0,ry=0;
reg [6:0] want[0:8];
integer targets[0:8],bases[0:8];
integer i,j,n,checks=0,tmp;
wire fh,ah,bh,eh;
wire [23:0] fc,ac,bc,ec;
`include "mod_targets.vh"
always #10 clk=~clk;
always @(posedge clk) begin rx<=in_pixel_x;ry<=in_pixel_y;end
ui_top_renderer dut(CONNECTIONS);
filter_panel_renderer reference_filter(.clk(clk),.rst_n(rst_n),.in_x(rx),.in_y(ry),
    .val_flt_power(1'b1),.val_flt_type(2'd0),.flt_cutoff(want[2]),.flt_res(want[3]),.out_hit_flt(fh),.out_flt_rgb(fc));
osc_panel_renderer reference_osc(.clk(clk),.rst_n(rst_n),.in_x(rx),.in_y(ry),
    .val_osca_power(1'b1),.val_oscb_power(1'b1),.val_osca_wave(2'd0),.val_oscb_wave(2'd0),
    .wt_pos_a(want[0]),.wt_pos_b(want[1]),.out_hit_osca(ah),.out_osca_rgb(ac),.out_hit_oscb(bh),.out_oscb_rgb(bc));
env_panel_renderer reference_env(.clk(clk),.rst_n(rst_n),.in_x(rx),.in_y(ry),.val_env_tab(2'd0),
    .env_attack(want[4]),.env_hold(want[5]),.env_decay(want[6]),.env_sustain(want[7]),.env_release(want[8]),
    .out_hit_env(eh),.out_env_rgb(ec));
task packet;
    input integer x,y;input down;
    begin @(negedge clk);ui_touch_x=x;ui_touch_y=y;ui_touch_down=down;ui_touch_valid=1;
        @(negedge clk);ui_touch_valid=0;repeat(12)@(negedge clk);end
endtask
task click;
    input integer x,y;
    begin packet(x,y,1);packet(0,0,0);end
endtask
task flat_wave;
    input integer level;
    begin
        for(j=0;j<7;j=j+1)click(832+j*64,543-level);
        repeat(1200)@(negedge clk);
        if(dut.lfo_nodes!=={7{level[6:0]}})$fatal(1,"Touch waveform edit failed");
    end
endtask
task expected;
    input integer wave,depth;input bound;
    begin for(j=0;j<9;j=j+1)begin
        tmp=bases[j]+(bound ? ((depth*wave)>>>7) : 0);
        want[j]=tmp<0 ? 0 : tmp>127 ? 127 : tmp;
    end end
endtask
task scan;
    input integer mode;
    begin
        repeat(1200)@(negedge clk);
        for(n=0;n<2304;n=n+1)begin
            @(negedge clk);
            case(n%4)
                0:begin in_pixel_x=870+((n*17)%372);in_pixel_y=106+((n*13)%128);end
                1:begin in_pixel_x=38+((n*19)%372);in_pixel_y=106+((n*11)%128);end
                2:begin in_pixel_x=454+((n*19)%372);in_pixel_y=106+((n*11)%128);end
                3:begin in_pixel_x=38+((n*17)%350);in_pixel_y=406+((n*13)%172);end
            endcase
            @(posedge clk);#1;
            if(n>12)begin
                if({dut.hit_flt,dut.flt_rgb}!=={fh,fc})$fatal(1,"Filter preview disconnected mode=%d n=%d",mode,n);
                if({dut.hit_osca,dut.osca_rgb,dut.hit_oscb,dut.oscb_rgb}!=={ah,ac,bh,bc})
                    $fatal(1,"OSC preview disconnected mode=%d n=%d",mode,n);
                if({dut.hit_env,dut.env_rgb}!=={eh,ec})$fatal(1,"ENV preview disconnected mode=%d n=%d",mode,n);
                checks=checks+1;
            end
        end
    end
endtask
initial begin
    targets[0]=10;targets[1]=19;targets[2]=23;targets[3]=24;
    for(i=4;i<9;i=i+1)targets[i]=i+25;
    bases[0]=20;bases[1]=30;bases[2]=50;bases[3]=20;
    bases[4]=10;bases[5]=10;bases[6]=30;bases[7]=40;bases[8]=30;
    expected(0,0,0);
    repeat(8)@(negedge clk);rst_n=1;scan(0);
    for(i=0;i<9;i=i+1)begin
        click(1140,385);click(mod_cx(targets[i]),mod_cy(targets[i]));
        if(dut.mod_sources[targets[i]*2+:2]!=1)$fatal(1,"Binding input did not reach target");
    end
    flat_wave(0);expected(0,64,1);scan(1);
    flat_wave(127);expected(127,64,1);scan(2);
    flat_wave(64);expected(64,64,1);scan(3);
    // Every target receives -64, exercising the real AMOUNT buttons.
    for(i=0;i<9;i=i+1)begin
        click(mod_cx(targets[i]),mod_cy(targets[i]));
        for(j=0;j<16;j=j+1)click(1030,675);
        if($signed(dut.mod_depths[targets[i]*8+:8])!=-64)$fatal(1,"Depth input did not reach target");
    end
    flat_wave(127);expected(127,-64,1);scan(4);
    click(1030,268);click(1190,675);want[3]=20;scan(5);
    if(dut.mod_sources[48+:2]!=0)$fatal(1,"CLEAR did not restore base RES");
    // Preview must not mutate any base input/state to achieve the animation.
    for(i=0;i<9;i=i+1)
        if(dut.mod_base[targets[i]*7+:7]!=bases[i])$fatal(1,"LFO wrote back into base bank");
    if(checks<13000)$fatal(1,"Insufficient scope pixel coverage");
    $display("PASS: %0d pixel comparisons, real bindings and waveform edits, OSC A/B/FILTER/ENV effective values, positive/negative depth, CLEAR and base isolation",checks);
    $finish;
end
initial begin #15000000;$fatal(1,"Scope preview timeout");end
endmodule
'''.replace('CONNECTIONS',',\n'.join(connections))
    (out/'tb_modulated_scopes.v').write_text(tb)
    def run(args,name):
        with (out/name).open('w') as f:
            subprocess.run([str(a) for a in args],cwd=out,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=180)
    run([MS/'vlib.exe','work'],'vlib.log')
    files=[ROOT/e.attrib['path'] for e in ET.parse(ROOT/'2_ui_touch_hub.gprj').findall('.//File') if e.attrib['path'].endswith('.v')]
    if args.renderer_ref:
        old=out/'ui_top_renderer_before.v'
        old.write_bytes(subprocess.check_output(['git','show',args.renderer_ref+':rtl/ui_vector_engine/ui_top_renderer.v'],cwd=ROOT))
        files=[old if p==ROOT/'rtl/ui_vector_engine/ui_top_renderer.v' else p for p in files]
    run([MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*files,'tb_modulated_scopes.v'],'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_modulated_scopes','-do','onerror {quit -code 1}; run -all; quit -f'],'vsim.log')
    log=(out/'simulation.log').read_text(errors='replace')
    if args.renderer_ref:
        if 'preview disconnected mode=' not in log:raise RuntimeError('Old renderer did not reproduce bug: '+str(out))
        print('PASS: old renderer reproduces disconnected modulated scope pixels; '+str(out))
        return
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:raise RuntimeError(str(out))
    print(next(x for x in log.splitlines() if 'PASS:' in x));print(out)
if __name__=='__main__':main()
