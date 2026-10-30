from pathlib import Path
from datetime import datetime
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'impl'/('phone_download_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
jdk=Path(json.loads(Path('D:/tools/android_hc07/runtime_20261030/toolchain.json').read_text())['jdk'])
sources=[ROOT/'phone_android/src/cn/gaoyun/performance/WavDownloadStore.java',ROOT/'sim/WavDownloadStoreTest.java']
commands=[['node',ROOT/'tools/test_phone_download.js'],[jdk/'bin/javac.exe','-encoding','UTF-8','-d',out,*sources],
          [jdk/'bin/java.exe','-cp',out,'WavDownloadStoreTest',out]]
for i,cmd in enumerate(commands):
    r=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,errors='replace',timeout=60)
    (out/f'step_{i}.log').write_text(r.stdout+r.stderr,encoding='utf-8')
    if r.returncode:raise RuntimeError(r.stdout+r.stderr)
    print(r.stdout,flush=True)
inputs=sources+[ROOT/'performance_web/phone_app.js',ROOT/'performance_web/protocol.js',ROOT/'tools/test_phone_download.js',Path(__file__)]
(out/'result.json').write_text(json.dumps({'passed':True,'hardware_tested':False,'source_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}},indent=2))
print(out)
