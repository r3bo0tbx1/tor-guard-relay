import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess as sp
import tarfile
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("backup",ROOT/"scripts/utilities/relay_backup.py")
backup=importlib.util.module_from_spec(spec); spec.loader.exec_module(backup)

class ArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("age"): raise unittest.SkipTest("age unavailable")
        cls.tmp=tempfile.TemporaryDirectory(dir="/dev/shm" if Path("/dev/shm").is_dir() else None)
        cls.directory=Path(cls.tmp.name)
        cls.identity=cls.directory/"identity"
        sp.run(["age-keygen","-o",str(cls.identity)],check=True,stderr=sp.DEVNULL)
        cls.recipient=sp.check_output(["age-keygen","-y",str(cls.identity)],text=True).strip()
    @classmethod
    def tearDownClass(cls): cls.tmp.cleanup()
    def make_archive(self, *, extra=None, corrupt_manifest=False):
        output=io.BytesIO(); records={}
        with tarfile.open(fileobj=output,mode="w:gz") as archive:
            for name,content in {"data/keys/secret_id_key":b"synthetic\x00key", "data/fingerprint":b"Test AABB",
                                 "config/etc/tor/torrc":b"DataDirectory /var/lib/tor\n"}.items():
                backup.add_bytes(archive,name,content,records)
            if extra: archive.addfile(extra)
            if corrupt_manifest: records["data/keys/secret_id_key"]["sha256"]="0"*64
            manifest={"format":1,"config_path":"/etc/tor/torrc","fingerprint":"Test AABB","files":records}
            backup.add_bytes(archive,"manifest.json",json.dumps(manifest).encode(),{})
        path=self.directory/(self.id().split(".")[-1]+".age")
        path.write_bytes(sp.check_output(["age","-r",self.recipient],input=output.getvalue()))
        return argparse.Namespace(archive=path,identity=str(self.identity),max_bytes=1024*1024)
    def test_complete_stream_and_checksums(self):
        self.assertEqual(backup.validate_archive(self.make_archive())["format"],1)
    def test_wrong_identity_rejected(self):
        args=self.make_archive()
        key=self.directory/"wrong"
        sp.run(["age-keygen","-o",str(key)],check=True,stderr=sp.DEVNULL)
        args.identity=str(key)
        with self.assertRaises(Exception): backup.validate_archive(args)
    def test_truncated_ciphertext_rejected(self):
        args=self.make_archive(); args.archive.write_bytes(args.archive.read_bytes()[:-15])
        with self.assertRaises(Exception): backup.validate_archive(args)
    def test_authenticated_bad_manifest_rejected(self):
        with self.assertRaises(ValueError): backup.validate_archive(self.make_archive(corrupt_manifest=True))
    def test_traversal_rejected_before_extract(self):
        bad=tarfile.TarInfo("data/../../escape")
        with self.assertRaises(ValueError): backup.validate_archive(self.make_archive(extra=bad))
    def test_link_rejected(self):
        bad=tarfile.TarInfo("data/link"); bad.type=tarfile.SYMTYPE; bad.linkname="/etc/passwd"
        with self.assertRaises(ValueError): backup.validate_archive(self.make_archive(extra=bad))
    def test_duplicate_rejected(self):
        bad=tarfile.TarInfo("data/fingerprint")
        with self.assertRaises(ValueError): backup.validate_archive(self.make_archive(extra=bad))
    def test_existing_restore_destination_untouched(self):
        args=self.make_archive(); args.destination=str(self.directory); args.validation_image=None
        marker=self.directory/"existing"; marker.write_text("keep")
        with self.assertRaises(ValueError): backup.restore(args)
        self.assertEqual(marker.read_text(),"keep")

class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.dir=Path(self.tmp.name); self.bin=self.dir/"bin"; self.bin.mkdir()
        self.proc=self.dir/"proc"; (self.proc/"123").mkdir(parents=True)
        (self.proc/"123/stat").write_text("123 (tor) "+" ".join(["S"]+["0"]*18+["50"])+"\n")
        (self.proc/"123/comm").write_text("tor\n")
        self.cfg=self.dir/"torrc"; self.cfg.write_text("Nickname Test\nExitRelay 0\n")
        (self.proc/"123/cmdline").write_bytes(b"tor\x00-f\x00"+str(self.cfg).encode()+b"\x00")
        self.log=self.dir/"notices.log"; self.log.write_text("Bootstrapped 100%\n")
        self.state=self.dir/"state"
        self.state.write_text(f"pid=123\nstart=50\ninode={self.log.stat().st_ino}\noffset={self.log.stat().st_size}\n")
        for name,content in {"pgrep":"echo 123","ps":"echo '123 0:01'","tor":'if [ "$1" = --version ]; then echo "Tor version 0.4.9.14."; fi'}.items():
            p=self.bin/name; p.write_text("#!/bin/sh\n"+content+"\n"); p.chmod(0o755)
        self.env={**os.environ,"PATH":str(self.bin)+":"+os.environ["PATH"],"PROC_ROOT":str(self.proc),
                  "RELAY_STATE":str(self.state),"RELAY_LIB":str(ROOT/"lib"),"TOR_CONFIG":str(self.cfg),
                  "TOR_LOG_DIR":str(self.dir),"TOR_DATA_DIR":str(self.dir)}
    def tearDown(self): self.tmp.cleanup()
    def health(self):
        result=sp.run(["sh",str(ROOT/"tools/health")],env=self.env,capture_output=True,text=True)
        return result,json.loads(result.stdout)
    def test_previous_run_bootstrap_is_ignored(self):
        _,health=self.health(); self.assertEqual(health["bootstrap"],0); self.assertFalse(health["readiness"])
    def test_current_run_bootstrap_is_seen(self):
        with self.log.open("a") as out: out.write("Bootstrapped 100%\n")
        _,health=self.health(); self.assertTrue(health["readiness"])
    def test_multiple_pids_are_not_concatenated(self):
        (self.proc/"456").mkdir(); (self.proc/"456/comm").write_text("tor\n")
        (self.proc/"456/cmdline").write_bytes(b"tor\x00-f\x00/etc/tor/torrc\x00")
        result,health=self.health(); self.assertNotEqual(result.returncode,0)
        self.assertEqual(health["reason"],"process_ambiguous"); self.assertEqual(health["pid"],0)
    def test_log_replacement_is_stale(self):
        self.log.rename(self.dir/"rotated.log"); self.log.write_text("Bootstrapped 100%\n")
        _,health=self.health(); self.assertFalse(health["readiness"]); self.assertFalse(health["fresh"])
    def test_concurrent_config_verifier_is_not_a_relay(self):
        (self.proc/"456").mkdir(); (self.proc/"456/comm").write_text("tor\n")
        (self.proc/"456/cmdline").write_bytes(b"tor\x00--verify-config\x00-f\x00/etc/tor/torrc\x00")
        result,health=self.health()
        self.assertEqual(result.returncode,0); self.assertEqual(health["pid"],123)
    def test_vanished_process_is_skipped(self):
        (self.proc/"456").mkdir(); (self.proc/"456/comm").write_text("tor\n")
        result,health=self.health()
        self.assertEqual(result.returncode,0); self.assertEqual(health["pid"],123)
        self.assertEqual(result.stderr,"")
    def test_redacted_diff_never_prints_values(self):
        self.cfg.write_text("HashedControlPassword SECRET-A\n")
        candidate=self.dir/"candidate"; candidate.write_text("HashedControlPassword SECRET-B\nContactInfo secret@example.com\n")
        result=sp.run(["sh",str(ROOT/"tools/config"),"diff",str(candidate)],env=self.env,capture_output=True,text=True)
        self.assertNotIn("SECRET",result.stdout); self.assertNotIn("secret@example.com",result.stdout)

class ReleaseNotesTests(unittest.TestCase):
    def test_gitmoji_scope_and_multiline_breaking_body(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args): return sp.run(["git","-C",directory,*args],check=True,capture_output=True,text=True)
            git("init"); git("config","user.name","Fixture"); git("config","user.email","fixture@example.invalid")
            git("-c","commit.gpgsign=false","commit","--allow-empty","-m","initial")
            git("tag","v1.0.0")
            git("-c","commit.gpgsign=false","commit","--allow-empty","-m","✨ feat(backup): Encrypt recovery", "-m","Details.\n\nBREAKING CHANGE: old restore is replaced")
            result=sp.check_output(["python3",str(ROOT/"scripts/release/generate_release_notes.py"),"2.2.0","1.0.0"],cwd=directory,text=True)
            self.assertIn("## Added",result); self.assertIn("## Compatibility and breaking changes",result)
            self.assertIn("Encrypt recovery",result); self.assertNotIn("## Other",result)
