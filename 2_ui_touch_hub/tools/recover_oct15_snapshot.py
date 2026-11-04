"""Recover pre-Git source state from recorded literal edits, without executing logs.

The base is the first Git commit f206be4. Reverse only recorded RTL edits
after the user's 2026-10-15 23:35 session start and before that commit.
Require every reverse match and an exact forward round trip before saving.
This writes an isolated source archive, never the active project files.
"""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TRANSCRIPT = Path(r"C:\Users\胡珂\.gemini\antigravity\brain\44b86f26-de1b-41bc-bc6c-1efd36abce37\.system_generated\logs\transcript_full.jsonl")
BASE = "f206be4"


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def main():
    edits = []
    prefix = "d:/github/gaoyun/2_ui_touch_hub/"
    for line in TRANSCRIPT.open(encoding="utf-8"):
        entry = json.loads(line)
        step = entry.get("step_index", 0)
        if not 4156 < step < 5799:
            continue
        for call in entry.get("tool_calls", []):
            args = call.get("args", {})
            path = str(args.get("TargetFile", "")).replace("\\", "/").lower()
            if (call.get("name") == "replace_file_content" and path.startswith(prefix)
                    and path.endswith((".v", ".vh", ".cst", ".sdc", ".gprj"))):
                edits.append((step, path[len(prefix):], args["TargetContent"], args["ReplacementContent"]))
    names = git("ls-tree", "-r", "--name-only", BASE).decode().splitlines()
    names = [n for n in names if n.startswith(("rtl/", "constraints/"))
             or n in ("2_ui_touch_hub.gprj", "build.tcl", "usb_hid_host_rom.mem")]
    base = {n: git("show", BASE + ":" + n).decode("utf-8-sig").replace("\r\n", "\n") for n in names}
    recovered = base.copy()
    for step, path, old, new in reversed(edits):
        old, new = old.replace("\r\n", "\n"), new.replace("\r\n", "\n")
        current = recovered[path]
        if step == 4790:
            # That edit deleted a duplicate tail. Its replacement is only
            # two 'end' lines, so use its recorded unchanged Stage 1 context.
            suffix = "\n\n    always @(posedge clk or negedge rst_n) begin\n        if (!rst_n) begin\n            s1_valid"
            assert current.count(new + suffix) == 1, "Ambiguous step 4790 context"
            current = current.replace(new + suffix, old + suffix, 1)
        else:
            assert new and current.count(new) == 1, (step, path, current.count(new))
            current = current.replace(new, old, 1)
        recovered[path] = current
    replay = recovered.copy()
    for step, path, old, new in edits:
        old, new = old.replace("\r\n", "\n"), new.replace("\r\n", "\n")
        assert replay[path].count(old) == 1, ("forward", step, path)
        replay[path] = replay[path].replace(old, new, 1)
    assert replay == base, "Round-trip differs from the first Git commit"
    output = ROOT / "impl" / "recovered_20261015_2335_verified"
    output.mkdir(exist_ok=False)
    manifest = {"target": "2026-10-15T23:35:15+08:00 before step 4156",
                "base_commit": BASE, "reversed_steps": [e[0] for e in edits],
                "round_trip": "exact normalized text match", "files": {}}
    for name, content in recovered.items():
        dest = output / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8", newline="\n")
        manifest["files"][name] = hashlib.sha256(dest.read_bytes()).hexdigest()
    (output / "recovery_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Recovered {len(names)} files, reversed {len(edits)} edits, exact forward round trip.")
    print(output)


if __name__ == "__main__":
    main()
