"""Collect source-only preset acceptance; never starts EDA or hardware tools."""
from pathlib import Path
import argparse,hashlib,json,subprocess,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 parser=argparse.ArgumentParser()
 for flag in ('preset_run','ui_run','elaboration','regression','fx_run','legacy_baseline'):
  parser.add_argument('--'+flag.replace('_','-'),type=Path,required=True)
 args=parser.parse_args();reports={};all_hashes={}
 for label,directory in vars(args).items():
  path=directory/'result.json';r=json.loads(path.read_text(encoding='utf-8'))
  assert r['passed'],label
  if 'workspace_matches_snapshot' in r:assert r['workspace_matches_snapshot'],label
  for name,h in r.get('source_sha256',{}).items():
   p=Path(name);p=p if p.is_absolute() else ROOT/p
   assert sha(p)==h,(label,str(p),'stale source')
   key=str(p.relative_to(ROOT));assert key not in all_hashes or all_hashes[key]==h,key
   all_hashes[key]=h
  reports[label]={'path':str(path),'sha256':sha(path),'passed':True}
 current_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
 branch=subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()
 assert branch=='integration/dual-138k-uart-phase1'
 unchanged=['rtl/midi_uart_tx/midi_uart_tx.v','rtl/ui_vector_engine/params.vh',
            'rtl/ui_vector_engine/mod_targets.vh','build.tcl','build_debug.tcl']
 for name in unchanged:
  original=subprocess.check_output(['git','show',current_commit+':2_ui_touch_hub/'+name],cwd=ROOT)
  assert original.replace(b'\r\n',b'\n')==(ROOT/name).read_bytes().replace(b'\r\n',b'\n'),name
 schema=json.loads((ROOT/'doc/SYNTH_CUSTOM_PRESET_SCHEMA_V1.json').read_text(encoding='utf-8'))
 catalog=json.loads((ROOT/'tools/synth_presets_reference.json').read_text(encoding='utf-8'))
 for row in catalog['rows']:
  assert len(row['ui_values'])==74
  for value,field in zip(row['ui_values'],schema['properties']['values']['prefixItems']):
   assert isinstance(value,int) and field['minimum']<=value<=field['maximum']
   if 'enum' in field:assert value in field['enum']
 projects={}
 required={'rtl/midi_uart_tx/synth_preset_controller.v','rtl/ui_vector_engine/synth_preset_ui.v','rtl/ui_vector_engine/synth_preset_panel.v'}
 for project in ('2_ui_touch_hub.gprj','2_ui_touch_hub_debug.gprj'):
  names=[e.attrib['path'] for e in ET.parse(ROOT/project).findall('.//File')]
  assert required.issubset(names)
  names+=list(str(p.relative_to(ROOT)) for p in (ROOT/'rtl/ui_vector_engine').glob('*.vh'))
  names+=[project,'build_debug.tcl' if 'debug' in project else 'build.tcl']
  projects[project]={name:sha(ROOT/name) for name in dict.fromkeys(names)}
 actual=(args.preset_run/'preset_actual.hex').read_text().split()
 expected=(args.preset_run/'preset_expected.hex').read_text().split()
 assert [int(s,16) for s in actual]==[int(s,16) for s in expected] and len(actual)==11343
 r=json.loads((args.regression/'result.json').read_text());assert len(r['tests'])==16
 output={'passed':True,'scope':'source and RTL simulation only; no Gowin or programming',
   'git_base_commit':current_commit,'git_branch':branch,'changes_committed':False,
   'reference_commit':catalog['reference_commit'],'reference_sha256':catalog['reference_sha256'],
   'reports':reports,'serial_bytes_checked':len(actual),'factory_presets':12,'complete_cc_values':888,
   'legacy_pixel_oracle_passed':False,'preexisting_legacy_failure_verified':True,
   'unchanged_protocol_and_build_files':unchanged,'matched_test_input_sha256':all_hashes,
   'project_input_review_only':projects,'custom_snapshot_schema_values_checked':888,
   'physical_acceptance_done':False,'timing_or_resources_audited':False}
 target=ROOT/'doc/SYNTH_FACTORY_PRESETS_2026-11-02.acceptance.json'
 target.write_text(json.dumps(output,indent=2)+'\n',encoding='utf-8')
 print(f'PASS: {len(reports)} evidence groups, {len(all_hashes)} matching test inputs, 12 presets/11343 serial bytes, both project input sets; no build/hardware. {target}')
if __name__=='__main__':main()
