#!/usr/bin/env python3
from pathlib import Path
import json
import subprocess as sp
import shutil
import os
import tempfile
root=Path(__file__).resolve().parents[2]
json_files=list((root/"templates").rglob("*.json"))
yaml_files=list((root/"templates").rglob("*.yml"))
assert json_files and yaml_files, "Template discovery empty"
for path in json_files: json.loads(path.read_text(encoding="utf-8"))
cli=os.environ.get("DOCKER","") or (shutil.which("docker.exe") if os.environ.get("WSL_DISTRO_NAME") else None) or shutil.which("docker")
if not cli: raise SystemExit("Docker Compose is required for template validation")
windows_cli=bool(os.environ.get("WSL_DISTRO_NAME")) and cli.lower().endswith(".exe")
with tempfile.TemporaryDirectory(dir=root, prefix=".compose-check-") as directory:
    fixture=Path(directory)/"fixture.env"
    fixture.write_text("EMAIL=operator@example.com\nNICKNAME=TemplateTest\nOR_PORT=9001\nPT_PORT=9002\n", encoding="utf-8")
    env_file=str(fixture)
    if windows_cli: env_file=sp.check_output(["wslpath","-w",env_file],text=True).strip()
    for path in yaml_files:
        native=str(path)
        if windows_cli: native=sp.check_output(["wslpath","-w",native],text=True).strip()
        sp.run([cli,"compose","--env-file",env_file,"-f",native,"config","--quiet"],check=True)
print(f"Validated {len(json_files)} JSON and {len(yaml_files)} Compose templates recursively")
