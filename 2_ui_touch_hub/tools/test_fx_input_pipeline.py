"""Exercise the exact production FX operand/touch stages and event arbitration."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MS = Path('D:/altera/modelsim_ase/win32aloem')


def main():
    top = (ROOT / 'rtl/ui_touch_hub_top.v').read_text(encoding='utf-8')
    renderer = (ROOT / 'rtl/ui_vector_engine/ui_top_renderer.v').read_text(encoding='utf-8')
    operands = top.split('    reg physical_fx_valid;', 1)[1].split('    // Other controls', 1)[0]
    operands = '    reg physical_fx_valid;' + operands
    touch = renderer.split('    reg fx_touch_valid,fx_touch_down;', 1)[1].split('    fx_editor_state u_fx_state', 1)[0]
    touch = '    reg fx_touch_valid,fx_touch_down;' + touch
    assert '.external_param_valid(physical_fx_valid)' in top
    assert '.touch_valid(fx_touch_valid),.touch_down(fx_touch_down)' in renderer
    tb = r'''`timescale 1ns/1ps
`include "params.vh"
module tb_fx_input_pipeline;
reg clk=0,rst_n=0;always #10 clk=~clk;
wire clk_pixel=clk,sys_rst_n_sync=rst_n;
reg spi_param_valid=0;reg [7:0] spi_param_id=0;
reg signed [7:0] physical_delta=0;
reg [132:0] fx_parameter_snapshot=0;
wire physical_fx=spi_param_id==`PARAM_ID_FX_REVERB || spi_param_id==`PARAM_ID_FX_DELAY;
reg ui_touch_valid=0,synth_touch_down=0,binding_capture=0;
reg [13:0] ui_touch_x=0,ui_touch_y=0;
OPERANDS
TOUCH
wire [132:0] values;wire event_valid;wire [7:0] event_id;wire [6:0] event_value;
integer events=0;reg [7:0] last_id;reg [6:0] last_value;
fx_editor_state dut(.clk(clk),.rst_n(rst_n),
 .touch_valid(fx_touch_valid),.touch_down(fx_touch_down),.touch_x(fx_touch_x),.touch_y(fx_touch_y),
 .external_valid(physical_fx_valid),.external_id(physical_fx_id),.external_value(physical_fx_value),
 .values(values),.event_valid(event_valid),.event_id(event_id),.event_value(event_value));
always @(posedge clk)if(event_valid)begin events=events+1;last_id=event_id;last_value=event_value;end
integer base,dir,which,expected,before_events,checks=0;
task drain;begin @(negedge clk);spi_param_valid=0;ui_touch_valid=0;repeat(8)@(negedge clk);end endtask
task packet;input integer px,py,down;
 begin @(negedge clk);ui_touch_x=px;ui_touch_y=py;synth_touch_down=down;ui_touch_valid=1;drain;end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
 for(which=0;which<2;which=which+1)
  for(base=0;base<128;base=base+1)
   for(dir=-8;dir<=8;dir=dir+1)begin
    @(negedge clk);before_events=events;
    spi_param_id=which ? `PARAM_ID_FX_REVERB : `PARAM_ID_FX_DELAY;
    fx_parameter_snapshot[0+:7]=base;fx_parameter_snapshot[42+:7]=base;
    physical_delta=dir;spi_param_valid=1;
    expected=base+dir;if(expected<0)expected=0;if(expected>127)expected=127;
    drain;
    if(events!=before_events+1 || last_id!=(which ? 8'h66 : 8'h60) || last_value!=expected)
     $fatal(1,"FX operand stage dropped/misaligned/clamped wrong base=%0d delta=%0d",base,dir);
    checks=checks+1;
   end
 // Same-cycle touch captures Delay Feedback (ID60); subsequent physical
 // edits cannot steal that captured parameter, even with pipeline latency.
 @(negedge clk);spi_param_valid=1;spi_param_id=`PARAM_ID_FX_DELAY;
 fx_parameter_snapshot[0+:7]=50;physical_delta=0;drain;
 packet(448,416,1); // FX index zero center, captured at 50
 before_events=events;
 @(negedge clk);spi_param_valid=1;spi_param_id=`PARAM_ID_FX_DELAY;
 fx_parameter_snapshot[0+:7]=90;physical_delta=8;
 ui_touch_valid=1;synth_touch_down=1;ui_touch_x=448;ui_touch_y=396;
 drain;
 if(events!=before_events+1 || last_id!=8'h60 || last_value!=60)
  $fatal(1,"Touch/physical arbitration lost capture or packet alignment");
 packet(0,0,0);
 before_events=events;
 @(negedge clk);spi_param_valid=1;spi_param_id=`PARAM_ID_OSCA_WT_POS;drain;
 if(events!=before_events)$fatal(1,"Non-FX knob leaked into FX state");
 // Reset while a valid operand is pending must discard it.
 @(negedge clk);spi_param_valid=1;spi_param_id=`PARAM_ID_FX_DELAY;
 @(negedge clk);rst_n=0;spi_param_valid=0;repeat(3)@(negedge clk);
 before_events=events;rst_n=1;repeat(8)@(negedge clk);
 if(events!=before_events)$fatal(1,"Pending operand survived reset");
 $display("PASS: %0d production FX operand cases, both targets/all bases/signed clamps, aligned touch ownership, non-FX suppression and pending reset",checks);
 $finish;
end
initial begin #5000000;$fatal(1,"FX input stage timeout");end
endmodule
'''.replace('OPERANDS', operands).replace('TOUCH', touch)
    out = ROOT / 'impl' / ('fx_input_pipeline_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    (out / 'tb.v').write_text(tb, encoding='utf-8')

    def run(name, args):
        p = subprocess.run(list(map(str, args)), cwd=out, capture_output=True,
                           text=True, errors='replace', timeout=120)
        log = p.stdout + p.stderr
        (out / (name + '.log')).write_text(log, encoding='utf-8')
        if p.returncode or any(t in log for t in ('** Error:', '** Fatal:', '# FAIL:')):
            raise RuntimeError(f'{name} failed: {out}')
        return log

    run('library', [MS / 'vlib.exe', 'work'])
    run('compile', [MS / 'vlog.exe', '-sv', '+incdir+' + str(ROOT / 'rtl/ui_vector_engine'),
                    ROOT / 'rtl/ui_vector_engine/fx_editor_state.v', out / 'tb.v'])
    log = run('simulation', [MS / 'vsim.exe', '-c', 'tb_fx_input_pipeline', '-do', 'run -all; quit -f'])
    assert '# PASS:' in log, out
    inputs = ['rtl/ui_touch_hub_top.v', 'rtl/ui_vector_engine/ui_top_renderer.v',
              'rtl/ui_vector_engine/fx_editor_state.v', 'rtl/ui_vector_engine/fx_controls.vh']
    hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in inputs}
    (out / 'result.json').write_text(json.dumps(dict(passed=True, source_sha256=hashes), indent=2))
    print(next(line for line in log.splitlines() if '# PASS:' in line))
    print(out)


if __name__ == '__main__':
    main()
