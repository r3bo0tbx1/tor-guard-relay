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
for path in json_files: json.loads(path.read_text())
cli=os.environ.get("DOCKER","") or (shutil.which("docker.exe") if os.environ.get("WSL_DISTRO_NAME") else None) or shutil.which("docker")
with tempfile.NamedTemporaryFile(mode="w", dir=root, prefix=".compose-check-", suffix=".env") as fixture:
    fixture.write("EMAIL=operator@example.com\nNICKNAME=TemplateTest\nOR_PORT=9001\nPT_PORT=9002\n"); fixture.flush()
    env_file=fixture.name
    if cli and cli.endswith(".exe"): env_file=sp.check_output(["wslpath","-w",env_file],text=True).strip()
    for path in yaml_files:
        native=str(path)
        if cli and cli.endswith(".exe"): native=sp.check_output(["wslpath","-w",native],text=True).strip()
        sp.run([cli,"compose","--env-file",env_file,"-f",native,"config","--quiet"],check=True)
print(f"Validated {len(json_files)} JSON and {len(yaml_files)} Compose templates recursively")
