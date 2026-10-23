"""Capture to a fresh audit directory without programming or overwriting images."""
from pathlib import Path
from datetime import datetime
from deploy_verified import remote,capture
root=Path(__file__).resolve().parents[1]
out=root/'impl'/('connection_check_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
out.mkdir(exist_ok=False)
dest='D:/gaoyun_deploy/'+out.name
print(remote(f"New-Item -ItemType Directory -Path '{dest}' -ErrorAction Stop | Out-Null").decode())
capture(dest,out)
print(out,flush=True)
