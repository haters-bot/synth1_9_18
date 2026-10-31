"""Check the imported local preview against WTB bytes and production RTL.

No synthesis or board access. All generated test files remain on E:.
"""
from pathlib import Path
from datetime import datetime
import argparse, hashlib, json, struct, subprocess, sys
from import_wavetable_catalog import import_catalog

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')
sys.stdout.reconfigure(encoding='utf-8',errors='replace')

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('bank',type=Path)
 args=parser.parse_args()
 out=Path('E:/gaoyun_builds')/('wavetable_preview_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
 out.mkdir();print(out,flush=True)
 catalog=out/'catalog'
 (catalog/'rtl/ui_vector_engine').mkdir(parents=True);(catalog/'doc').mkdir()
 metadata=import_catalog(args.bank,catalog)
 assert metadata['count']==10,'bench currently targets the shipped 10-table bank'
 generated=['wavetable_catalog.vh','wavetable_preview_data.vh','wavetable_preview_map.vh']
 for name in generated:
  assert (catalog/'rtl/ui_vector_engine'/name).read_bytes()==(ROOT/'rtl/ui_vector_engine'/name).read_bytes(),name
 data=args.bank.read_bytes();gold=[]
 for bank in range(10):
  pcm=struct.unpack_from('<65536h',data,32+bank*131072)
  for position in range(128):
   anchor,remainder=divmod(position*15,127);weight=remainder*128//127
   for phase in range(128):
    left=pcm[anchor*17*256+phase*2]>>8
    right=pcm[min(anchor+1,15)*17*256+phase*2]>>8
    gold.append(f'{((left*(128-weight)+right*weight)>>9)&127:02x}')
 (out/'preview_expected.hex').write_text('\n'.join(gold)+'\n',encoding='ascii')
 ui=ROOT/'rtl/ui_vector_engine'
 sources=[ui/'osc_panel_renderer.v',ui/'sine_table.v',ROOT/'sim/tb_wavetable_preview.v']
 inputs=sources+list(ui.glob('*.vh'))+[Path(__file__),ROOT/'tools/import_wavetable_catalog.py',args.bank]
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
 snapshot=out/'src';snapshot.mkdir()
 for p in sources+list(ui.glob('*.vh')):(snapshot/p.name).write_bytes(p.read_bytes())
 def run(name,cmd):
  r=subprocess.run(list(map(str,cmd)),cwd=out,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=240)
  log=r.stdout+r.stderr;(out/(name+'.log')).write_text(log,encoding='utf-8')
  if r.returncode or any(marker in log for marker in ['** Error:','** Fatal:','FATAL:']):
   raise RuntimeError(name+': '+str(out)+'\n'+log[-6000:])
  return log
 run('library',[MS/'vlib.exe','work'])
 run('compile',[MS/'vlog.exe','-sv','+incdir+'+str(snapshot),*[snapshot/p.name for p in sources]])
 log=run('simulation',[MS/'vsim.exe','-c','tb_wavetable_preview','-do','onerror {quit -code 1}; run -all; quit -f'])
 assert 'PASS:' in log,log
 assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
 result={'passed':True,'workspace_matches_snapshot':True,'source_sha256':hashes,'samples_checked':2*(len(gold)+128+2),
         'preview_rom_bytes':metadata['preview']['rom_bytes'],'synthesis_run':False,'hardware_tested':False}
 (out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 print(next(line for line in log.splitlines() if 'PASS:' in line),flush=True)

if __name__=='__main__':main()
