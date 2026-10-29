"""对流水线改造做逐样本回归；参考RTL来自固定Git检查点，临时产物放tmp。"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BASELINE = 'e6c28a68f8fea164f7a4e39ae6d79baf73ae2d26'
OUT = ROOT / 'tmp' / 'timing_pipeline_regression'
OUT.mkdir(parents=True, exist_ok=True)
NAMES = ['global_distortion', 'global_phaser', 'global_chorus', 'global_filter',
         'oscillator_tdm_core', 'wavetable_phase_warp']
for name in NAMES:
    source = subprocess.check_output(['git', 'show', f'{BASELINE}:src/{name}.v'], cwd=ROOT).decode('utf-8-sig')
    source = source.replace('module ' + name, 'module ' + name + '_reference', 1)
    if name == 'oscillator_tdm_core':
        source = source.replace('wavetable_phase_warp u_', 'wavetable_phase_warp_reference u_')
    (OUT / f'{name}_reference.v').write_text(source, encoding='utf-8')

def ports(name):
    source = (ROOT / 'src' / f'{name}.v').read_text(encoding='utf-8-sig')
    header = source[:source.index(');')]
    return re.findall(r'\b(input|output)\s+(?:wire|reg)\s+(signed\s+)?(\[[^\]]+\]\s*)?(\w+)', header)

# 独立效果块并行接收相同输入。对比按样本序号，不按时钟周期。
tb = '''`timescale 1ns/1ps
module tb_effects_equivalence;
reg clk=0; always #10 clk=~clk;
reg rst_n=0;
'''
inputs={}
for name in NAMES[:4]:
    for direction,sign,width,port in ports(name):
        if direction=='input' and port not in ['clk','rst_n']: inputs[port]=(sign,width)
for port,(sign,width) in inputs.items(): tb+=f'reg {sign}{width}{port}=0;\n'
for i,name in enumerate(NAMES[:4]):
    tb+=f'wire ready{i}, old_ready{i}, valid{i}, old_valid{i}, overrun{i}, old_overrun{i};\nwire signed [15:0] data{i}, old_data{i};\n'
    for suffix,inst,pre in [('',f'dut{i}',''),('_reference',f'ref{i}','old_')]:
        con=[]
        for direction,_,_,port in ports(name):
            val={'in_ready':pre+f'ready{i}','out_valid':pre+f'valid{i}','sample_out':pre+f'data{i}','input_overrun':pre+f'overrun{i}'}.get(port,port)
            con.append(f'.{port}({val})')
        tb+=f'{name}{suffix} {inst}('+','.join(con)+');\n'
    tb+=f'''reg [15:0] expected{i}[0:12000]; integer sent{i}=0, got{i}=0;
always @(posedge clk) begin
    #1;
    if (!rst_n) begin sent{i}=0; got{i}=0; end
    else begin
        if (old_valid{i}) begin expected{i}[sent{i}]=old_data{i}; sent{i}=sent{i}+1; end
        if (valid{i}) begin
            if (got{i} >= sent{i} || data{i} !== expected{i}[got{i}])
                $fatal(1,"{name} sample %0d got %h expected %h",got{i},data{i},expected{i}[got{i}]);
            got{i}=got{i}+1;
        end
        if (overrun{i} || old_overrun{i}) $fatal(1,"{name} overrun");
    end
end
'''
tb+='integer n, seed=20261029;\ninitial begin\nrepeat(4) @(negedge clk); rst_n=1;\nfor(n=0;n<12000;n=n+1) begin\n'
tb+='if (!(ready0 && ready1 && ready2 && ready3)) $fatal(1,"96kHz deadline missed");\n'
for port in inputs:
    if port=='in_valid': continue
    value={'enable':'(n%19 != 0)','distortion_type':'n%3','mix_control':'(n%3==0)?0:((n%3==1)?127:64)','filter_mode':'(n/200)%7','sample_in':'(n%17==0)?16\'h8000:((n%17==1)?16\'h7fff:$random(seed))'}.get(port,'$random(seed)')
    tb+=f'{port}={value};\n'
tb+='in_valid=1; @(negedge clk); in_valid=0;\n'
# 接收后改变外部参数，确认整个样本使用接收时快照。
for port in inputs:
    if port not in ['in_valid']: tb+=f'{port}=$random(seed);\n'
tb+='repeat(519) @(negedge clk);\n'
for i in range(4): tb+=f'if(got{i}!=n+1 || sent{i}!=n+1) $fatal(1,"lost output {i}");\n'
tb+='end\n$display("PASS: 12000 samples/effect bit exact, feedback wrap and 520-clock budget"); $finish; end\nendmodule\n'
(OUT/'tb_effects_equivalence.sv').write_text(tb,encoding='utf-8')

# 所有地址、模式、深度穷举，检查组合兼容接口与两级流水接口。
tb='''`timescale 1ns/1ps
module tb_warp_equivalence;
reg clk=0; always #10 clk=~clk;
reg rst_n=0;
reg [7:0] raw_address=0;
reg [3:0] warp_mode=0;
reg [6:0] warp_amount=0;
wire [7:0] old_value, new_value, piped;
reg [7:0] e1=0,e2=0; reg v1=0,v2=0;
wavetable_phase_warp_reference ref0(raw_address,warp_mode,warp_amount,old_value);
wavetable_phase_warp dut(raw_address,warp_mode,warp_amount,new_value);
wavetable_phase_warp_pipeline dutp(clk,rst_n,raw_address,warp_mode,warp_amount,piped);
always @(posedge clk) begin
 if(rst_n) begin e2=e1; e1=old_value; v2=v1; v1=1; #1;
 if(new_value!==old_value || (v2 && piped!==e2)) $fatal(1,"warp mismatch"); end
end
integer m,a,p;
initial begin repeat(3) @(negedge clk); rst_n=1;
for(m=0;m<16;m=m+1) for(a=0;a<128;a=a+1) for(p=0;p<256;p=p+1) begin
 warp_mode=m; warp_amount=a; raw_address=p; @(negedge clk);
end
repeat(3) @(negedge clk);
$display("PASS: exhaustive 524288 Warp inputs and pipeline alignment"); $finish;
end
endmodule
'''
(OUT/'tb_warp_equivalence.sv').write_text(tb,encoding='utf-8')

# 32槽位，真实Detune和初始相位均打开；按帧比较混音和全部音符状态。
tb='''`timescale 1ns/1ps
module tb_core_equivalence;
localparam PARTIAL_SUM_WIDTH=24;
reg clk=0; always #10 clk=~clk;
reg rst_n=0;
'''
for direction,sign,width,port in ports('oscillator_tdm_core'):
    if direction=='input' and port not in ['clk','rst_n','cache_load_clk','cache_load_rst_n']: tb+=f'reg {sign}{width}{port}=0;\n'
for suffix,inst in [('', 'dut'),('_reference','ref0')]:
    con=[]
    for direction,_,_,port in ports('oscillator_tdm_core'):
        val={'cache_load_clk':'clk','cache_load_rst_n':'rst_n'}.get(port,port) if direction=='input' else ''
        con.append(f'.{port}({val})')
    tb+=f'oscillator_tdm_core{suffix} #(.SLOTS_PER_ENGINE(32),.INITIAL_PHASE_ENABLE(1),.REALTIME_DETUNE_ENABLE(1),.ENVELOPE_UPDATE_DIV(1)) {inst}('+','.join(con)+');\n'
tb+='''integer n,k,j,age,kind, seed=4101, latency=0, max_latency=0;
time batch_time;
reg [23:0] old_sum, new_sum; integer old_count=0,new_count=0; reg compare_enabled=1;
always @(posedge clk) begin #1;
 if(rst_n) begin
  if(start_tick) batch_time=$time;
  if(ref0.partial_valid) begin old_sum=ref0.partial_sum; old_count=old_count+1; end
  if(dut.partial_valid) begin
   latency=($time-batch_time)/20; if(latency>max_latency) max_latency=latency;
   new_sum=dut.partial_sum; new_count=new_count+1;
   if(compare_enabled && (old_count!=new_count || new_sum!==old_sum)) $fatal(1,"core sum frame=%0d new=%h old=%h",n,new_sum,old_sum);
  end
  if(dut.schedule_overrun) $fatal(1,"core scheduling overrun");
 end
end
task configure;
 input integer slot;
 input en;
 begin
  task_update_valid=1; task_update_slot=slot; task_update_enable=en;
  task_update_phase_reset=1; task_update_phase_step=32'h123456+slot*12345;
  task_update_base_step=task_update_phase_step;
  task_update_detune_unit=12345+slot*456;
  task_update_detune_magnitude=slot%8; task_update_detune_negative=slot%2;
  task_update_velocity=127-slot*3; task_update_initial_phase=32'habcd1234+slot*123456789;
  @(negedge clk); task_update_valid=0;
 end
endtask
task batch;
 begin
 start_tick=1; @(negedge clk); start_tick=0;
 for(j=1;j<65;j=j+1) begin
  @(negedge clk);
 end
 if(dut.busy) $fatal(1,"core missed deadline");
 end
endtask
initial begin
 repeat(4) @(negedge clk); rst_n=1;
 attack_phase_step=32'h20000000; decay_phase_step=32'h10000000;
 release_phase_step=32'h08000000; sustain_level=16'h6543;
 // 两个缓存bank使用不同数据，在帧间切换，验证同步读与混音的对应关系。
 for(k=0;k<1024;k=k+1) begin
  cache_write_enable=1; cache_write_bank=k/512; cache_write_frame=(k/256)%2;
  cache_write_address=k%256; cache_write_data=k*173;
  @(negedge clk);
 end
 cache_write_enable=0; cache_commit_bank=0; cache_commit_fraction=67; cache_commit_toggle=1;
 repeat(8) @(negedge clk);
 for(k=0;k<32;k=k+1) configure(k,1);
 for(n=0;n<1500;n=n+1) begin
  waveform_select=n%5; warp_mode=(n/5)%12; warp_amount=$random(seed); wt_position=$random(seed);
  external_wavetable_enable=(n/40)%2;
  if(n%100==0) begin
   cache_commit_bank=~cache_commit_bank; cache_commit_fraction=$random(seed); cache_commit_toggle=~cache_commit_toggle;
   repeat(8) @(negedge clk);
  end
  detune_amount=$random(seed); vibrato_ratio_delta_q16=$random(seed);
  glide_override_enable=n%2; glide_override_base_step=32'h7654321+n*123456;
  if(n%25==0) configure((n/25)%32,0);
  if(n%25==10) configure((n/25)%32,1);
  batch;
  for(k=0;k<32;k=k+1) begin
'''
for state in ['phase_state','enable_state','gate_state','envelope_stage','envelope_level','velocity_envelope_level','envelope_phase','release_start_level']:
    tb+=f'if(dut.{state}[k]!==ref0.{state}[k]) $fatal(1,"{state} frame=%0d slot=%0d",n,k);\n'
tb+='''  end
 end
 $display("PASS: 1500 x 32 slots bit exact; measured core completion clock=%0d",max_latency);
 compare_enabled=0;
 // 在读槽、Warp、ROM、样本、增益及最终提交各拍注入同槽Note On/Off或清相位。
 for(kind=0;kind<4;kind=kind+1) for(age=1;age<=8;age=age+1) begin
  rst_n=0; repeat(3) @(negedge clk); rst_n=1;
  waveform_select=2; attack_phase_step=32'hffffffff; decay_phase_step=32'hffffffff;
  sustain_level=16'hffff; glide_override_enable=0; vibrato_ratio_delta_q16=0;
  configure(0,1); repeat(4) batch;
  start_tick=1; @(negedge clk); start_tick=0;
  repeat(age-1) @(negedge clk);
  if(kind<2) configure(0,kind==0);
  else if(kind==3) begin rst_n=0; @(negedge clk); rst_n=1; end
  else begin clear_phase=1; @(negedge clk); clear_phase=0; end
  repeat(55) @(negedge clk);
  if(dut.busy) $fatal(1,"cancel stalled pipeline");
  if(kind==0 && (dut.phase_state[0]!==task_update_initial_phase || dut.envelope_stage[0]!==1 || dut.envelope_phase[0]!==0))
   $fatal(1,"stale retrigger write age=%0d",age);
  if(kind==1 && (dut.gate_state[0]!==0 || dut.envelope_stage[0]!==4 || dut.envelope_phase[0]!==0))
   $fatal(1,"stale noteoff write age=%0d",age);
  if(kind==3 && (dut.partial_valid || dut.phase_state[0]!==0 || dut.enable_state[0]!==0)) $fatal(1,"reset did not flush pipeline");
  if(kind==2 && dut.phase_state[0]!==0) $fatal(1,"stale clear-phase write age=%0d",age);
 end
 $display("PASS: all 32 in-flight retrigger/noteoff/clear/reset cases"); $finish;
end
endmodule
'''
(OUT/'tb_core_equivalence.sv').write_text(tb,encoding='utf-8')
files=['global_svf_filter','global_comb_filter','global_filter','global_distortion','global_phaser','global_chorus',
       'sine_lut','triangle_lut','square_lut','sawtooth_lut','wavetable_phase_warp','acid_wavetable_rom','acid_wavetable_reader','wavetable_frame_cache','oscillator_tdm_core']
rel=OUT.relative_to(ROOT).as_posix()
tcl='onerror {quit -code 1 -f}\nonbreak {}\nif {![file isdirectory sim/work_timing_pipeline]} {vlib sim/work_timing_pipeline}\nvmap work_timing_pipeline sim/work_timing_pipeline\n'
tcl+='vlog -sv -work work_timing_pipeline '+' '.join(f'src/{f}.v' for f in files)+' '+' '.join(f'{rel}/{n}_reference.v' for n in NAMES)+' '+' '.join(f'{rel}/tb_{t}_equivalence.sv' for t in ['effects','warp','core'])+'\n'
for name in ['effects','warp','core']:
    tcl+=f'vsim -c -lib work_timing_pipeline tb_{name}_equivalence\nonfinish stop\nrun -all\nquit -sim\n'
tcl+='quit -code 0 -f\n'
(OUT/'run.do').write_text(tcl,encoding='utf-8')
result=subprocess.run(['vsim','-c','-do',f'do {rel}/run.do'],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
log=result.stdout.decode(errors='replace');(OUT/'regression.log').write_text(log,encoding='utf-8')
for line in log.splitlines():
    if any(word in line for word in ['PASS:','Fatal','Error:','Warning:']): print(line)
print('Log:',OUT/'regression.log')
if result.returncode or log.count('PASS:')!=4 or '** Fatal:' in log: sys.exit(1)

