"""Test the production native MIDI reader and phone UI, without a phone."""
from pathlib import Path
from datetime import datetime
import subprocess,json,hashlib,sys
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
ROOT=Path(__file__).resolve().parents[1]
out=Path('E:/gaoyun_builds')/('phone_selection_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir()
jdk=Path(json.loads(Path('D:/tools/android_hc07/runtime_20261030/toolchain.json').read_text())['jdk'])
sources=[ROOT/'phone_android/src/cn/gaoyun/performance/MidiDocumentReader.java',ROOT/'sim/MidiDocumentReaderTest.java',
         ROOT/'phone_android/src/cn/gaoyun/performance/WavDownloadStore.java',ROOT/'sim/WavDownloadStoreTest.java']
scripts=['test_midi_adaptation.js','test_phone_midi_selection.js','test_phone_client.js','test_phone_download.js','test_phone_handshake.js','test_phone_resume.js']
inputs=sources+[ROOT/'tools'/n for n in scripts]+[ROOT/'performance_web'/n for n in ['phone_app.js','protocol.js','midi.js','index.html','style.css','examples/Twinkle_Twinkle_90bpm_C4_A4.mid']]+[ROOT/'phone_android/src/cn/gaoyun/performance/MainActivity.java',ROOT/'phone_android/AndroidManifest.xml',Path(__file__)]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
commands=[[jdk/'bin/javac.exe','-encoding','UTF-8','-d',out,*sources],
 [jdk/'bin/java.exe','-cp',out,'MidiDocumentReaderTest'],[jdk/'bin/java.exe','-cp',out,'WavDownloadStoreTest',out],
 *[['node',ROOT/'tools'/n] for n in scripts]]
for i,cmd in enumerate(commands):
 r=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
 (out/f'step_{i}.log').write_text(r.stdout+r.stderr,encoding='utf-8')
 if r.returncode:raise RuntimeError(r.stdout+r.stderr)
 print(r.stdout.strip())
matches=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
(out/'result.json').write_text(json.dumps({'passed':matches,'device_tested':False,'workspace_matches_snapshot':matches,'source_sha256':hashes},indent=2))
if not matches:raise RuntimeError('Workspace changed during phone tests')
print(out)
