"""Download verified local APK tools to D: without installing or executing them."""
from pathlib import Path
import hashlib
import json
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

DEST = Path("D:/tools/android_hc07/runtime_20261030")


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=90) as response:
        return response.read()


def archive(url, name, algorithm, checksum):
    path = DEST / name
    if not path.exists():
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=120) as source, path.open("xb") as target:
            while chunk := source.read(1024 * 1024):
                target.write(chunk)
    digest = hashlib.new(algorithm, path.read_bytes()).hexdigest()
    if digest.lower() != checksum.lower():
        raise RuntimeError(f"Checksum mismatch; preserve and inspect {path}")
    output = DEST / path.stem
    if not output.exists():
        output.mkdir()
        with zipfile.ZipFile(path) as package:
            for member in package.infolist():
                if not (output / member.filename).resolve().is_relative_to(output.resolve()):
                    raise RuntimeError("Unsafe archive path")
            package.extractall(output)
    print(json.dumps({"url": url, "file": str(path), "hash": digest, "extracted": str(output)}), flush=True)
    return output


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    assets = json.loads(fetch("https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows"))
    package = assets[0]["binary"]["package"]
    jdk = archive(package["link"], "temurin17.zip", "sha256", package["checksum"])
    tree = ET.fromstring(fetch("https://dl.google.com/android/repository/repository2-1.xml"))
    packages = {node.attrib.get("path"): node for node in tree if node.tag.endswith("remotePackage")}
    outputs = {"jdk": str(next(jdk.glob("*/bin/javac.exe")).parents[1])}
    for key, sdkpath in (("platform", "platforms;android-35"), ("build_tools", "build-tools;35.0.0")):
        node = packages[sdkpath]
        entries = node.findall("./archives/archive")
        candidate = next(a for a in entries if a.findtext("host-os") in (None, "windows"))
        complete = candidate.find("complete")
        link = "https://dl.google.com/android/repository/" + complete.findtext("url")
        checksum = complete.find("checksum")
        folder = archive(link, key + "35.zip", checksum.attrib.get("type", "sha1"), checksum.text)
        outputs[key] = str(next(folder.iterdir()))
    (DEST / "toolchain.json").write_text(json.dumps(outputs, indent=2), encoding="utf-8")
    print(json.dumps(outputs), flush=True)


if __name__ == "__main__":
    main()
