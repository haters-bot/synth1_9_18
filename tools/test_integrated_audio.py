"""Validate merged MIDI/pitch/top RTL and compare speaker audio to origin/main.

The full-top runs use a mathematical FIR model and PLL/DDR interface stubs;
they do not prove the encrypted IP's cycle timing or physical DDR behavior.
"""
from datetime import datetime
from pathlib import Path
import hashlib,json,shutil,subprocess,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')

def main():
    out=ROOT/'impl'/('integrated_audio_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir(parents=True);print(out,flush=True)
    sources=[]
    for f in ET.parse(ROOT/'synth1_9_18.gprj').findall('.//File'):
        p=Path(f.attrib['path'])
        if f.attrib.get('enable')=='1' and p.suffix in ('.v','.sv') and p.parent.as_posix() not in (
            'src/advanced_fir_filter','src/ddr3_memory_interface','src/gowin_ddr_pll','src/gowin_pll'):
            sources.append(ROOT/p)
    sources += [ROOT/'sim'/p for p in ('fir_decimator_8x_ip_model.v','sys_pll_50m_ip_stub.v',
        'ddr3_vendor_ip_stubs.v','tb_performance_pitch_controller.v','tb_pitch_modulated_core.v',
        'tb_top_midi_input.v','tb_top_dual_unison8.v')]
    coeff=ROOT/'ip/fir_decimator_8x/coeff_q17.txt'
    shutil.copy2(coeff,out/'coeff_q17.txt')
    (out/'src').mkdir();shutil.copy2(ROOT/'src/acid_wavetable_16x256.hex',out/'src/acid_wavetable_16x256.hex')
    baseline_ref=subprocess.check_output(['git','rev-parse','origin/main'],cwd=ROOT,text=True).strip()
    baseline=subprocess.check_output(['git','show',baseline_ref+':src/top.v.v'],cwd=ROOT).decode('utf-8')
    baseline=baseline.replace('module top #(', 'module top_audio_baseline #(',1)
    (out/'top_audio_baseline.v').write_text(baseline,encoding='utf-8')
    tb=(ROOT/'sim/tb_top_dual_unison8.v').read_text(encoding='utf-8')
    tb=tb.replace('module tb_top_dual_unison8;', 'module tb_audio_visual_preservation;',1)
    extra='''
    wire baseline_bclk,baseline_lrck,baseline_din;
    integer speaker_checks=0,nonzero_samples=0;
    top_audio_baseline #(.UART_BAUD_RATE(TEST_UART_BAUD),
        .CONTROL_UART_BAUD_RATE(TEST_UART_BAUD),.KEYBOARD_UART_BAUD_RATE(TEST_UART_BAUD),
        .DEFAULT_UNISON_COUNT(1),.OSC_ENGINE_COUNT(2),.SLOTS_PER_ENGINE(32),
        .EXTERNAL_WAVETABLE_ENABLE(0)) baseline(
        .sys_clk(sys_clk),.rst_n(rst_n),.uart_rx(uart_rx),
        .control_uart_rx(control_uart_rx),.keyboard_uart_rx(keyboard_uart_rx),
        .sd_dat0(sd_dat0),.MAX_BCLK(baseline_bclk),.MAX_LRC(baseline_lrck),.MAX_DIN(baseline_din));
    always @(posedge sys_clk)begin
        #2;
        if(rst_n && dut.rst_n_sys)begin
            if({MAX_BCLK,MAX_LRC,MAX_DIN} !== {baseline_bclk,baseline_lrck,baseline_din}
               || dut.master_output_sample !== baseline.master_output_sample)
                $fatal(1,"OSC analysis taps changed speaker data or timing");
            speaker_checks=speaker_checks+1;
            if(dut.sample_tick && dut.master_output_sample!=0)nonzero_samples=nonzero_samples+1;
        end
    end
'''
    tb=tb.replace('    always #10 sys_clk = ~sys_clk;',extra+'\n    always #10 sys_clk = ~sys_clk;',1)
    tb=tb.replace('        if (errors == 0)', '''        if(speaker_checks<50000 || nonzero_samples<100)
            $fatal(1,"Insufficient nonzero speaker comparison coverage");
        $display("PASS: %0d full-top bit-exact speaker comparisons against main, %0d nonzero final samples; FIR mathematical model",speaker_checks,nonzero_samples);
        if (errors == 0)''',1)
    (out/'tb_audio_visual_preservation.v').write_text(tb,encoding='utf-8')
    sources += [out/'top_audio_baseline.v',out/'tb_audio_visual_preservation.v']
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[coeff]}
    def run(name,args):
        p=subprocess.run(list(map(str,args)),cwd=out,capture_output=True,text=True,errors='replace',timeout=300)
        log=p.stdout+p.stderr;(out/(name+'.log')).write_text(log,encoding='utf-8')
        if p.returncode or any(x in log for x in ('** Error:','** Fatal:','# FAIL:','# ERROR:')):
            raise RuntimeError(out/(name+'.log'))
        return log
    run('library',[MS/'vlib.exe','work'])
    run('compile',[MS/'vlog.exe','-sv',*sources])
    run('full_top_elaboration',[MS/'vsim.exe','-c','top','-do','run 0; quit -f'])
    benches=['tb_performance_pitch_controller','tb_pitch_modulated_core','tb_top_midi_input',
             'tb_top_dual_unison8','tb_audio_visual_preservation']
    for bench in benches:
        log=run(bench,[MS/'vsim.exe','-c',bench,'-do','run -all; quit -f'])
        assert '# PASS:' in log,out/(bench+'.log')
        print('\n'.join(s for s in log.splitlines() if '# PASS:' in s),flush=True)
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    (out/'result.json').write_text(json.dumps(dict(passed=True,baseline=baseline_ref,
        fir_model='mathematical, not vendor cycle timing',source_sha256=hashes),indent=2))
if __name__=='__main__':main()
