"""Independent Python-Git oracle + full production state/UART RTL regression."""
from pathlib import Path
from datetime import datetime
import ast,hashlib,json,subprocess,types
from generate_synth_presets import ROOT,REFERENCE,reference_data,expanded_rows
from simulation_sources import project_verilog_sources
MS=Path('D:/altera/modelsim_ase/win32aloem')

class Variable:
 def __init__(self,value): self.value=value
 def get(self): return self.value
 def set(self,value): self.value=value

def python_oracle(raw,ns,preset):
 # Execute the ACTUAL pinned send_all method and its helpers, not a second
 # manually transcribed ordering table or the generated RTL table.
 methods={'send_all_synth_controls','send_filter_mode_selection','send_effect_mode_selection',
          'send_distortion_type_selection','send_waveform_selection','send_warp_mode_selection',
          'send_oscillator_enable','send_synth_control','send_filter_lfo_configuration'}
 proto=subprocess.check_output(['git','show',REFERENCE+':tools/lfo_v2_protocol.py'],cwd=ROOT).decode('utf-8')
 env=dict(ns);exec(compile(proto,'pinned_lfo_v2_protocol','exec'),env)
 found={}
 for node in ast.walk(ast.parse(raw.decode('utf-8'))):
  if isinstance(node,ast.FunctionDef) and node.name in methods:
   exec(compile(ast.Module([node],type_ignores=[]),'pinned_sender_methods','exec'),env)
   found[node.name]=env[node.name]
 assert set(found)==methods
 obj=types.SimpleNamespace()
 for name,method in found.items():setattr(obj,name,types.MethodType(method,obj))
 result=[]
 def cc(controller,value,channel):
  assert channel==16 and 0<=value<=127
  result.extend([0xBF,controller,value]);return True
 def sx(parameter,value,**kwargs):result.extend(env['sysex'](parameter,value));return True
 obj.send_control_change=cc;obj.send_highres_parameter=sx
 obj.status=Variable('');obj.port=types.SimpleNamespace(is_open=True)
 obj.filter_lfo_config_after_id=None;obj._lfo_v2_sent={}
 for key,value in preset['controls'].items():setattr(obj,key,Variable(value))
 obj.osc_controls={osc:{k:Variable(v) for k,v in values.items()} for osc,values in preset['oscillators'].items()}
 points=[(i*7+11)%128 for i in range(21)]
 obj.filter_lfo_curves=[types.SimpleNamespace(values=points[b*7:b*7+7],stepped=bool(5&(1<<b))) for b in range(3)]
 obj.filter_lfo_rate=[Variable(env['RATES_HZ'][r]) for r in (3,4,7)]
 obj.filter_lfo_once=[Variable(bool(6&(1<<b))) for b in range(3)]
 obj.filter_lfo_enabled=[Variable(False) for _ in range(3)]
 obj.lfo_routes=[{'source':Variable('无'),'depth':Variable(0)} for _ in range(53)]
 obj.send_all_synth_controls()
 assert len(result)==708
 return result

def main():
 out=Path('E:/gaoyun_builds')/('synth_presets_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
 raw,ns=reference_data();rows=expanded_rows(ns)
 catalog=json.loads((ROOT/'tools/synth_presets_reference.json').read_text(encoding='utf-8'))
 assert catalog['rows']==json.loads(json.dumps(rows))
 expected=[python_oracle(raw,ns,row['full']) for row in rows]
 order=list(range(12))+[11,0,11,2]
 stream=sum((expected[n] for n in order),[])+[0xBF,0x30,0x19,0xF0,0x7D,0x4F,0x02,0x7F,0xF7,0xF0,0x7D,0x7E,0,0,0xF7]
 (out/'preset_expected.hex').write_text(''.join(f'{b:02x}\n' for b in stream))
 (out/'pinned_midi_uart_sender.py').write_bytes(raw)
 sources=project_verilog_sources(ROOT,'2_ui_touch_hub.gprj')+[ROOT/'sim/tb_synth_presets.v']
 inputs=list(dict.fromkeys(sources+list((ROOT/'rtl/ui_vector_engine').glob('*.vh'))+[ROOT/'2_ui_touch_hub.gprj',Path(__file__),ROOT/'tools/generate_synth_presets.py',ROOT/'tools/synth_presets_reference.json']))
 hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
 for p in inputs:
  target=out/'src'/p.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(p.read_bytes())
 def run(label,args):
  r=subprocess.run(list(map(str,args)),cwd=out,capture_output=True,text=True,errors='replace',timeout=240)
  log=r.stdout+r.stderr;(out/(label+'.log')).write_text(log)
  if r.returncode or any(x in log for x in ('** Error:','** Fatal:','FAIL:')):raise RuntimeError(str(out)+'\n'+log[-7000:])
  return log
 run('library',[MS/'vlib.exe','work'])
 run('compile',[MS/'vlog.exe','-sv','+incdir+'+str(out/'src/rtl/ui_vector_engine'),*[out/'src'/p.relative_to(ROOT) for p in sources]])
 log=run('uart',[MS/'vsim.exe','-c','tb_synth_presets','-do','onerror {quit -code 1}; run -all; quit -f'])
 assert 'PASS:' in log
 actual=[int(s,16) for s in (out/'preset_actual.hex').read_text().split()]
 assert actual==stream
 representatives={rows[n]['name']:{'complete_hex':' '.join(f'{b:02X}' for b in expected[n]),'bytes':len(expected[n])} for n in (0,5,6,11)}
 (out/'representative_midi.json').write_text(json.dumps(representatives,ensure_ascii=False,indent=2),encoding='utf-8')
 matches=all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
 result={'passed':True,'reference_commit':REFERENCE,'reference_sha256':hashlib.sha256(raw).hexdigest(),
         'presets':12,'cc_values':888,'complete_batch_bytes':708,'serial_bytes_checked':len(actual),
         'source_sha256':hashes,'workspace_matches_snapshot':matches,'gowin_or_hardware_used':False}
 (out/'result.json').write_text(json.dumps(result,indent=2))
 assert matches
 print('\n'.join(l for l in log.splitlines() if 'PASS:' in l or 'CHECK:' in l))
 print('PASS: byte-for-byte match against actual pinned Python send_all_synth_controls; '+str(out))

if __name__=='__main__':main()
