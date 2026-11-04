"""Build the dependency-free Android shell with verified D:-local SDK tools."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import shutil
import subprocess
import zipfile
import argparse

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output-root',type=Path,default=ROOT/'impl')
    args=parser.parse_args()
    config=json.loads(Path("D:/tools/android_hc07/runtime_20261030/toolchain.json").read_text())
    jdk,platform,tools=(Path(config[key]) for key in ("jdk","platform","build_tools"))
    out=args.output_root/("phone_apk_"+datetime.now().strftime("%Y%m%d_%H%M%S_%f"));out.mkdir(parents=True)
    classes=out/"classes";classes.mkdir();dex=out/"dex";dex.mkdir()
    def run(command,name):
        result=subprocess.run([str(v) for v in command],cwd=out,capture_output=True,text=True,errors="replace",timeout=180)
        (out/(name+".log")).write_text(result.stdout+result.stderr,encoding="utf-8")
        if result.returncode:raise RuntimeError(f"{name} failed: {out}\n{result.stdout}{result.stderr}")
    sources=list((ROOT/"phone_android/src").rglob("*.java"))
    run([jdk/"bin/javac.exe","-encoding","UTF-8","-source","8","-target","8","-classpath",platform/"android.jar","-d",classes,*sources],"javac")
    with zipfile.ZipFile(out/"classes.jar","w",zipfile.ZIP_DEFLATED) as package:
        for path in classes.rglob("*.class"):package.write(path,path.relative_to(classes).as_posix())
    run([jdk/"bin/java.exe","-cp",tools/"lib/d8.jar","com.android.tools.r8.D8","--lib",platform/"android.jar","--min-api","26","--output",dex,out/"classes.jar"],"dex")
    unsigned=out/"unsigned.apk"
    run([tools/"aapt.exe","package","-f","-M",ROOT/"phone_android/AndroidManifest.xml","-S",ROOT/"phone_android/res","-A",ROOT/"performance_web","-I",platform/"android.jar","-F",unsigned],"aapt")
    with zipfile.ZipFile(unsigned,"a",zipfile.ZIP_DEFLATED) as package:package.write(dex/"classes.dex","classes.dex")
    aligned=out/"aligned.apk"
    run([tools/"zipalign.exe","-f","4",unsigned,aligned],"align")
    keydir=ROOT/"impl/phone_signing";keydir.mkdir(exist_ok=True);keystore=keydir/"local-demo.p12"
    # Development key for this local, sideloaded build; not a publication key.
    if not keystore.exists():
        run([jdk/"bin/keytool.exe","-genkeypair","-keystore",keystore,"-storepass","local-demo-only","-keypass","local-demo-only","-alias","local","-keyalg","RSA","-keysize","2048","-validity","3650","-dname","CN=FPGA Local Demo"],"key")
    apk=out/"FPGA-Performance.apk"
    run([jdk/"bin/java.exe","-jar",tools/"lib/apksigner.jar","sign","--ks",keystore,"--ks-key-alias","local","--ks-pass","pass:local-demo-only","--out",apk,aligned],"sign")
    run([jdk/"bin/java.exe","-jar",tools/"lib/apksigner.jar","verify","--verbose","--print-certs",apk],"verify")
    run([tools/"aapt.exe","dump","badging",apk],"badging")
    inputs={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,ROOT/"phone_android/AndroidManifest.xml",*(ROOT/"phone_android/res").rglob("*.xml"),*(ROOT/"performance_web").glob("*")] if p.is_file()}
    manifest={"apk":str(apk),"sha256":hashlib.sha256(apk.read_bytes()).hexdigest(),"inputs":inputs,"device_tested":False}
    (out/"source_manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
    print(json.dumps({k:v for k,v in manifest.items() if k!="inputs"},ensure_ascii=False),flush=True)


if __name__=="__main__":main()
