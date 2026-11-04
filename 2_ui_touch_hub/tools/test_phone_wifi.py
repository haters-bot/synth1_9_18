"""Exercise the production Wi-Fi network lease against modeled Android callbacks."""
from pathlib import Path
from datetime import datetime
import hashlib,json,subprocess,sys,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]

def main():
    sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    out=Path('E:/gaoyun_builds')/('phone_wifi_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir(parents=True)
    jdk=Path(json.loads(Path('D:/tools/android_hc07/runtime_20261030/toolchain.json').read_text())['jdk'])
    helper=ROOT/'phone_android/src/cn/gaoyun/performance/WifiNetworkSession.java'
    sources=[helper,ROOT/'sim/WifiNetworkSessionTest.java',*(ROOT/'sim/phone_wifi_fakes').rglob('*.java')]
    manifest=ROOT/'phone_android/AndroidManifest.xml'
    tree=ET.parse(manifest);ns='{http://schemas.android.com/apk/res/android}'
    permissions={p.attrib[ns+'name'] for p in tree.getroot().findall('uses-permission')}
    assert {'android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.CHANGE_NETWORK_STATE'}<=permissions
    inputs=[*sources,manifest,ROOT/'phone_android/src/cn/gaoyun/performance/MainActivity.java',ROOT/'performance_web/phone_app.js',ROOT/'tools/test_phone_handshake.js',Path(__file__)]
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    commands=[[jdk/'bin/javac.exe','-encoding','UTF-8','-source','8','-target','8','-d',out,*sources],[jdk/'bin/java.exe','-cp',out,'WifiNetworkSessionTest']]
    for index,command in enumerate(commands):
        result=subprocess.run(list(map(str,command)),cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=45)
        (out/f'step_{index}.log').write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode:raise RuntimeError(result.stdout+result.stderr)
        print(result.stdout.strip())
    matches=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    (out/'result.json').write_text(json.dumps({'passed':matches,'device_tested':False,'workspace_matches_snapshot':matches,'source_sha256':hashes},indent=2),encoding='utf-8')
    if not matches:raise RuntimeError('Wi-Fi source changed during tests')
    print(out)

if __name__=='__main__':main()
