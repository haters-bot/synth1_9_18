"""Decode the actual MIDI output at 31250 baud with a physical 50 MHz clock."""
from datetime import datetime
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
    out=ROOT/'impl'/('midi_50mhz_tests_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    (out/'tb_midi_50mhz.v').write_text(r'''`timescale 1ns/1ps
`include "params.vh"
module tb_midi_50mhz;
reg clk=0,rst_n=0,note=0,cc=0;
always #10 clk=~clk;
wire uart,busy;
midi_uart_tx dut(.clk(clk),.rst_n(rst_n),.note_on_req(note),.note_off_req(1'b0),
    .note_number(7'd60),.note_velocity(7'd100),.cc_req(cc),
    .cc_param_id(`PARAM_ID_FLT_CUTOFF),.cc_val(7'd93),.uart_tx(uart),.tx_busy(busy));
integer count=0,i;
reg [7:0] actual,expected;
initial forever begin
    @(negedge uart);
    if(rst_n) begin
        #16000;
        if(uart!==0)$fatal(1,"Start bit not 31250 baud");
        for(i=0;i<8;i=i+1)begin #32000;actual[i]=uart;end
        #32000;
        if(uart!==1)$fatal(1,"Stop bit not 31250 baud");
        case(count)
            0:expected=8'h90;1:expected=60;2:expected=100;
            3:expected=8'hBF;4:expected=74;5:expected=93;
            default:$fatal(1,"Unexpected byte");
        endcase
        if(actual!==expected)$fatal(1,"31250 baud byte %0d got=%h expected=%h",count,actual,expected);
        count=count+1;
        if(count==6)begin
            $display("PASS: 50 MHz physical clock, 31250 baud, Note On and Filter CC decoded from serial pin");
            $finish;
        end
    end
end
initial begin
    repeat(5)@(negedge clk);rst_n=1;
    repeat(5)@(negedge clk);note=1;
    @(negedge clk);note=0;
    repeat(4)@(negedge clk);cc=1;
    @(negedge clk);cc=0;
end
initial begin #4000000;$fatal(1,"MIDI timeout");end
endmodule
''')
    subprocess.run([str(MS/'vlib.exe'),'work'],cwd=out,capture_output=True,check=True)
    with (out/'compile.log').open('w') as log:
        subprocess.run([str(MS/'vlog.exe'),'-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),
                        str(ROOT/'rtl/midi_uart_tx/midi_uart_tx.v'),'tb_midi_50mhz.v'],
                       cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(MS/'vsim.exe'),'-c','-l','simulation.log','tb_midi_50mhz','-do','run -all; quit -f'],
                   cwd=out,capture_output=True,check=True)
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:raise RuntimeError(f'Failed: {out}')
    print(next(x for x in log.splitlines() if 'PASS:' in x));print(out)

if __name__=='__main__':main()
