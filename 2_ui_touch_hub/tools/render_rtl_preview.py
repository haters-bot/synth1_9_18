"""Render one real ui_top_renderer RTL frame through ModelSim, without hardware.

Artifacts use a new impl directory per invocation. No reference image is altered.
"""
import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MODELSIM = Path('D:/altera/modelsim_ase/win32aloem')


def verify_caption_pixels(frame, filter_type):
    # Independent output-pixel check catches a one-clock layer offset,
    # which geometry-only checks cannot detect.
    font_data=json.loads((ROOT/'tools/ui_font_7x10.json').read_text())
    fg=(240,244,255);bg=(18,22,32)
    for text,origin in [('SINE',70),('SAW',486),
                        (['LOWPASS','HIGHPASS','BANDPASS','NOTCH'][filter_type],902)]:
        for i,char in enumerate(text):
            glyph=font_data['glyphs'][font_data['characters'].index(char)]
            for y in range(10):
                for x in range(8):
                    coverage=glyph[y][x] if x<7 else 0
                    alpha=(0,1,3,4)[coverage]
                    expected=tuple((alpha*f+(4-alpha)*b)//4 for f,b in zip(fg,bg))
                    actual=frame.getpixel((origin+i*8+x,56+y))
                    if actual!=expected:
                        raise RuntimeError(f'Caption pixel alignment/color at {text}/{i}/{x}/{y}: {actual} != {expected}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--lfo-tab', type=int, choices=range(3), default=0)
    parser.add_argument('--env-tab', type=int, choices=range(3), default=0)
    parser.add_argument('--filter-type', type=int, choices=range(4), default=0)
    parser.add_argument('--value', type=int, choices=range(128), metavar='0..127',
                        help='Override numeric parameters to check digit extremes')
    parser.add_argument('--demo-binding', action='store_true',
                        help='Drive real touch packets to bind LFO1 to cutoff and LFO2 to delay mix')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.label):
        parser.error('Use an ASCII artifact label')
    out = ROOT / 'impl' / ('ui_preview_' + datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + args.label)
    out.mkdir(exist_ok=False)
    source = (ROOT / 'rtl/ui_vector_engine/ui_top_renderer.v').read_text(encoding='utf-8')
    ports = source[source.index('module ui_top_renderer'):source.index(');')]
    connections = []
    live = {'clk', 'rst_n', 'in_pixel_x', 'in_pixel_y', 'in_den',
            'ui_touch_valid', 'ui_touch_down', 'ui_touch_x', 'ui_touch_y'}
    for match in re.finditer(r'input\s+wire\s*(?:signed\s*)?(\[\d+:\d+\])?\s*([^\n]+)', ports):
        width, names = match.groups()
        for name in names.split('//')[0].rstrip(' ,\r').split(','):
            name = name.strip()
            if not name:
                continue
            if name in live:
                value = name
            elif name.startswith('val_'):
                if name == 'val_env_tab':
                    value = str(args.env_tab)
                elif name == 'val_flt_type':
                    value = str(args.filter_type)
                elif 'power' in name or name == 'val_flt_route_a':
                    value = "1'b1"
                elif 'wave' in name:
                    value = "2'd1" if 'oscb' in name else "2'd0"
                elif any(part in name for part in ['type', 'tab', 'bypass', 'route', 'keytrack']):
                    value = '0'
                elif args.value is not None:
                    value = str(args.value)
                else:
                    value = str({'val_env_attack': 10, 'val_env_hold': 0,
                                 'val_env_decay': 40, 'val_env_sustain': 90,
                                 'val_env_release': 35, 'val_flt_cutoff': 80,
                                 'val_flt_res': 32, 'val_osca_unison': 1,
                                 'val_oscb_unison': 1, 'val_osca_wt_pos': 0}.get(name, 64))
            elif name == 'selected_param_id':
                value = "8'h30"
            else:
                value = '0'
            connections.append(f'.{name}({value})')
    connections += ['.out_den(out_den)', '.out_pixel_data(rgb)']
    tb = '''`timescale 1ns/1ps
module tb_ui_frame;
reg clk=0, rst_n=0, in_den=0;
reg [13:0] in_pixel_x=0, in_pixel_y=0;
reg ui_touch_valid=0, ui_touch_down=0;
reg [13:0] ui_touch_x=0, ui_touch_y=0;
wire out_den;
wire [23:0] rgb;
integer f, x, y, pixels=0;
integer dx_check, dy_check, geometry_checks=0, node_checks=0;
integer offset_index;
integer mm0,mm1,pbefore,pafter,da,db,c1,c2,c3,ref_h;
integer lfo_x, lfo_segment, lfo_fraction, lfo_a, lfo_b, lfo_expected, lfo_expected_q2, lfo_checks=0;
reg signed [8:0] offset_check;
reg signed [13:0] reference_dev;
always #8 clk=~clk;
task demo_packet;
    input integer px,py;input pressed;
    begin
        @(negedge clk);ui_touch_valid=1;ui_touch_down=pressed;ui_touch_x=px;ui_touch_y=py;
        @(negedge clk);ui_touch_valid=0;repeat(8) @(negedge clk);
    end
endtask
ui_top_renderer dut(CONNECTIONS);
always @(posedge clk) begin
    #1;
    if(rst_n && dut.u_knobs.s1_active) begin
        dx_check=$signed(dut.u_knobs.s1_dx);
        dy_check=$signed(dut.u_knobs.s1_dy);
        if(dut.u_knobs.s1_r2 !== dx_check*dx_check+dy_check*dy_check)
            $fatal(1,"Knob distance corrupted at dx=%0d dy=%0d",dx_check,dy_check);
        geometry_checks=geometry_checks+1;
    end
    if(rst_n && in_den) begin
        // Validate the actual node predicate over the entire raster, including
        // distant points where the original 14-bit square sum wrapped around.
        dx_check=in_pixel_x-400;
        dy_check=in_pixel_y-490;
        if(dut.u_env_scope.is_near_node(in_pixel_x,in_pixel_y,14'd400,14'd490)
            !== (dx_check*dx_check+dy_check*dy_check <= 25))
            $fatal(1,"False envelope node at %0d,%0d",in_pixel_x,in_pixel_y);
        if(dut.u_flt_scope.node_hit !==
            (dut.u_flt_scope.s0_pwr &&
             (int'(dut.u_flt_scope.ndx)*int'(dut.u_flt_scope.ndx)+
              int'(dut.u_flt_scope.ndy)*int'(dut.u_flt_scope.ndy) <= 20)))
            $fatal(1,"False filter node");
        node_checks=node_checks+1;
    end
    if(rst_n && dut.u_lfo_panel.graph1) begin
        lfo_x=int'(dut.u_lfo_panel.x1)-832;
        lfo_segment=lfo_x==384 ? 5 : lfo_x/64;
        lfo_fraction=lfo_x==384 ? 64 : lfo_x%64;
        lfo_a=(dut.lfo_nodes >> (lfo_segment*7)) & 127;
        lfo_b=(dut.lfo_nodes >> ((lfo_segment+1)*7)) & 127;
        pbefore=lfo_segment==0 ? lfo_a : (dut.lfo_nodes>>((lfo_segment-1)*7))&127;
        pafter=lfo_segment==5 ? lfo_b : (dut.lfo_nodes>>((lfo_segment+2)*7))&127;
        da=lfo_a-pbefore;db=lfo_b-lfo_a;
        mm0=lfo_segment==0 || da*db<=0 ? 0 : da>0 ? (da<db ? da:db) : (da>db ? da:db);
        da=lfo_b-lfo_a;db=pafter-lfo_b;
        mm1=lfo_segment==5 || da*db<=0 ? 0 : da>0 ? (da<db ? da:db) : (da>db ? da:db);
        c1=mm0;c2=3*(lfo_b-lfo_a)-2*mm0-mm1;c3=-2*(lfo_b-lfo_a)+mm0+mm1;
        ref_h=c3*lfo_fraction+c2*64;
        ref_h=ref_h*lfo_fraction+c1*4096;
        ref_h=(ref_h*lfo_fraction+lfo_a*262144)>>>12;
        if(dut.lfo_stepped && lfo_fraction!=64) ref_h=lfo_a*64;
        lfo_expected=ref_h>>6;
        if(dut.u_lfo_panel.curve_y !== 14'(543-lfo_expected))
            $fatal(1,"LFO interpolation mismatch at x=%0d",lfo_x);
        lfo_expected_q2=(543*64-ref_h)/16;
        if(dut.u_lfo_panel.curve_y_q2 !== lfo_expected_q2[15:0])
            $fatal(1,"LFO fractional interpolation mismatch at x=%0d",lfo_x);
        lfo_checks=lfo_checks+1;
    end
    if(out_den) begin
        if (^rgb === 1'bx) $fatal(1,"Unknown pixel at output %0d",pixels);
        $fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
        pixels=pixels+1;
    end
end
initial begin
    for(offset_index=0;offset_index<512;offset_index=offset_index+1) begin
        offset_check=offset_index;
        reference_dev=(offset_check*6'sd46)/8'sd128;
        if(dut.u_osc_scope.display_deviation(offset_check) !== reference_dev)
            $fatal(1,"Wave scaling mismatch for offset %0d",offset_check);
        reference_dev=($signed(offset_check)*18)/32;
        if(dut.u_osc_scope.display_deviation_q2(offset_check) !== reference_dev)
            $fatal(1,"Wave fractional scaling mismatch for offset %0d",offset_check);
    end
    f=$fopen("frame.ppm","wb");
    $fwrite(f,"P6\\n1280 720\\n255\\n");
    repeat(4) @(negedge clk); rst_n=1;
    repeat(4) @(negedge clk);
    ui_touch_valid=1; ui_touch_down=1; ui_touch_x=LFO_TAB_X; ui_touch_y=385;
    @(negedge clk); ui_touch_down=0;
    @(negedge clk); ui_touch_valid=0;
    repeat(1000) @(negedge clk);
    DEMO_BINDING
    for(y=0;y<720;y=y+1) begin
        if(y%120==0) $display("RTL frame progress: row %0d / 720",y);
        for(x=0;x<1280;x=x+1) begin
            @(negedge clk); in_den=1; in_pixel_x=x; in_pixel_y=y;
        end
        @(negedge clk); in_den=0;
        repeat(20) @(negedge clk);
    end
    repeat(8) @(negedge clk);
    $fclose(f);
    if(pixels!=921600) $fatal(1,"Wrong output size: %0d",pixels);
    if(lfo_checks!=49280) $fatal(1,"Incomplete LFO graph checks: %0d",lfo_checks);
    $display("PASS: complete RTL frame, no unknown pixels; %0d knob geometry checks; %0d node checks; %0d LFO interpolation checks",geometry_checks,node_checks,lfo_checks);
    $finish;
end
endmodule
'''.replace('CONNECTIONS', ',\n'.join(connections)).replace('LFO_TAB_X', str(850+88*args.lfo_tab))
    demo='''
    demo_packet(850,385,1);demo_packet(0,0,0);
    demo_packet(1140,385,1);demo_packet(0,0,0);
    demo_packet(980,485,1);demo_packet(950,268,1);demo_packet(0,0,0);
    demo_packet(930,385,1);demo_packet(0,0,0);
    demo_packet(1140,385,1);demo_packet(0,0,0);
    demo_packet(980,485,1);demo_packet(728,416,1);demo_packet(0,0,0);
    repeat(1000) @(negedge clk);
'''
    tb=tb.replace('DEMO_BINDING',demo if args.demo_binding else '')
    (out / 'tb_ui_frame.v').write_text(tb, encoding='utf-8')
    subprocess.run([str(MODELSIM/'vlib.exe'), 'work'], cwd=out, check=True, capture_output=True)
    ui = ROOT/'rtl/ui_vector_engine'
    import xml.etree.ElementTree as ET
    files = [str(ROOT / e.attrib['path']) for e in ET.parse(ROOT/'2_ui_touch_hub.gprj').findall('.//File') if e.attrib['path'].endswith('.v')]
    with (out/'compile.log').open('w') as log:
        subprocess.run([str(MODELSIM/'vlog.exe'), '-sv', '+incdir+'+str(ui),
                        *files, 'tb_ui_frame.v'], cwd=out, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run([str(MODELSIM/'vsim.exe'), '-c', '-l', 'simulation.log',
                    'tb_ui_frame', '-do', 'run -all; quit -f'], cwd=out, check=True, capture_output=True)
    log = (out/'simulation.log').read_text(errors='replace')
    if 'PASS: complete RTL frame' not in log:
        raise RuntimeError(f'Frame validation failed: {out}')
    from PIL import Image
    with Image.open(out/'frame.ppm') as frame:
        verify_caption_pixels(frame,args.filter_type)
        frame.save(out/'frame.png')
        frame.crop((24, 240, 1256, 360)).resize((1232, 120)).save(out/'knob_labels.png')
    print(out, flush=True)


if __name__ == '__main__':
    main()

