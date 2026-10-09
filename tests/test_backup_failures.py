import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess as sp
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("backup_failures", ROOT / "scripts/utilities/relay_backup.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class CreateFailureTests(unittest.TestCase):
    def setUp(self):
        if not shutil.which("age"):
            self.skipTest("age unavailable")
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name)
        key = self.directory / "identity"
        sp.run(["age-keygen", "-o", str(key)], check=True, stderr=sp.DEVNULL)
        recipients = self.directory / "recipients"
        recipients.write_bytes(sp.check_output(["age-keygen", "-y", str(key)]))
        self.args = argparse.Namespace(container="synthetic", recipients=str(recipients),
            output_dir=str(self.directory), passphrase=False, dry_run=False, stop=True,
            stop_timeout=45, max_bytes=1024**2, deployment_file=[], logs=False)
        self.calls = []

    def tearDown(self):
        self.tmp.cleanup()

    def info(self, running):
        return {"Name": "/synthetic", "Image": "sha256:fixture",
                "Config": {"Image": "fixture", "Labels": {}, "Env": [], "Cmd": []},
                "State": {"Running": running, "Pid": int(running)}, "Mounts": []}

    def run_failure(self, error, running=True):
        def docker(*args, **kwargs):
            self.calls.append(args)
            return sp.CompletedProcess(args, 0)
        with patch.object(backup, "inspect", side_effect=[self.info(running), self.info(False)]), \
             patch.object(backup, "config_files", return_value={"/etc/tor/torrc": b"DataDirectory /var/lib/tor\n"}), \
             patch.object(backup, "read_file", return_value=b"Test AABB"), \
             patch.object(backup, "ensure_quiescent"), \
             patch.object(backup, "docker", side_effect=docker), \
             patch.object(backup, "add_tree", side_effect=error), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(type(error)):
                backup.create(self.args)
        self.assertFalse(list(self.directory.glob("*.part")))
        self.assertFalse(list(self.directory.glob("*.tar.gz.age")))
        self.assertEqual(sum(call[0] == "start" for call in self.calls), int(running))

    def test_producer_failure_restarts_only_its_source(self):
        self.run_failure(ValueError("producer failed"))

    def test_disk_exhaustion_removes_partial_ciphertext(self):
        self.run_failure(OSError(28, "No space left on device"))

    def test_interruption_cleans_up_and_restarts(self):
        self.run_failure(KeyboardInterrupt())

    def test_already_stopped_source_is_not_started(self):
        self.run_failure(ValueError("producer failed"), running=False)

    def test_restart_failure_is_reported_with_original_failure(self):
        real_docker = backup.docker
        def docker(*args, **kwargs):
            if args[0] == "start":
                raise ValueError("synthetic restart failure")
            return sp.CompletedProcess(args, 0)
        with patch.object(backup, "inspect", side_effect=[self.info(True), self.info(False)]), \
             patch.object(backup, "config_files", return_value={"/etc/tor/torrc": b""}), \
             patch.object(backup, "read_file", return_value=b"Test AABB"), \
             patch.object(backup, "ensure_quiescent"), patch.object(backup, "docker", side_effect=docker), \
             patch.object(backup, "add_tree", side_effect=ValueError("producer failed")), \
             contextlib.redirect_stderr(io.StringIO()) as error:
            with self.assertRaisesRegex(ValueError, "producer failed"):
                backup.create(self.args)
        self.assertIn("Source restart also failed", error.getvalue())
        self.assertFalse(list(self.directory.glob("*.part")))
