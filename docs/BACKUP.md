# 🔐 Encrypted Backup & Recovery Guide

[Documentation](README.md) · [Deployment](DEPLOYMENT.md) · [Migration](MIGRATION.md)

Keep the relay identity, active torrc and transport state together. The host command streams a compressed tar archive directly into **age encryption**; it never writes a plaintext archive. Python 3.10+ and age are host dependencies, not image dependencies.

## 📋 Before you start

Run from the repository on Linux or WSL. With Docker Desktop, the command uses `docker.exe` from WSL when available. Set `DOCKER` to override the CLI. Store backups and private age identities in the Linux filesystem with restricted permissions; Windows-mounted directories do not provide the same Unix permission guarantees.

Create a recovery identity once, store its private key separately from the archives, and copy only its public recipient into the recipient file:

```sh
umask 077
mkdir -p "$HOME/.config/relay-backup" "$HOME/relay-backups"
age-keygen -o "$HOME/.config/relay-backup/identity.txt"
age-keygen -y "$HOME/.config/relay-backup/identity.txt" > "$HOME/.config/relay-backup/recipients.txt"
```

Use an existing organization recipient file if you already manage recovery keys. Losing every decryption identity makes the backup unrecoverable. External or offline Tor master keys are **not included** and need a separate encrypted recovery procedure.

## 📦 Create

Preview coverage first. The source must already have a fingerprint and keys.

```sh
sh scripts/utilities/relay-backup.sh create --container tor-relay \
  --recipients "$HOME/.config/relay-backup/recipients.txt" \
  --output-dir "$HOME/relay-backups" --dry-run

sh scripts/utilities/relay-backup.sh create --container tor-relay \
  --recipients "$HOME/.config/relay-backup/recipients.txt" \
  --output-dir "$HOME/relay-backups" --stop \
  --deployment-file templates/docker-compose/docker-compose-guard-env.yml
```

Replace the deployment-file path with your actual Compose or ENV file. Each optional file is encrypted too; use distinct basenames. Add `--logs` only when you need incident evidence. Interactive `--passphrase` replaces `--recipients`; never put a passphrase in command arguments or ENV variables.

A running source requires explicit `--stop`. The command waits for Docker to report it stopped with PID zero, refuses shared storage with another running container writer, and restarts only the source it stopped. A source already stopped remains stopped. A failure removes the partial ciphertext and attempts source restart; a restart failure is reported separately. The default stop timeout is 45 seconds.

| Included | Coverage |
| --- | --- |
| Configuration | Active torrc and supported recursive absolute includes |
| Identity and state | Entire effective DataDirectory, including keys, fingerprint, family material, state, caches and pt_state |
| Manifest | File hashes, modes, original paths, fingerprint, image identity and available build labels |
| Optional files | Explicit deployment files; logs with `--logs` |

The command supports exact absolute include files, flat absolute include globs and directories with a trailing slash. Relative includes, unmatched globs, links, special files and conflicting DataDirectory overrides fail closed. Host processes writing bind mounts cannot be detected through Docker; stop those writers yourself. The default total payload limit is 20 GiB, configurable with `--max-bytes`.

## ✅ Verify the complete archive

Use the filename printed by create:

```sh
sh scripts/utilities/relay-backup.sh verify "$HOME/relay-backups/BACKUP.tar.gz.age" \
  --identity "$HOME/.config/relay-backup/identity.txt"
```

Verification authenticates the complete age stream and reads every archived member, checking hashes against the encrypted manifest. It rejects truncated ciphertext, duplicate members, traversal, links, special files and unsafe permissions. A successful archive verification proves content integrity; rehearse recovery separately to prove operational recovery.

## 🔄 Restore into a new staging directory

Load a compatible local validation image first. Restore never pulls an image or starts a relay on the Tor network.

```sh
sh scripts/utilities/relay-backup.sh restore "$HOME/relay-backups/BACKUP.tar.gz.age" \
  --identity "$HOME/.config/relay-backup/identity.txt" \
  --destination "$HOME/relay-restored" \
  --validation-image tor-relay:2.2.0-local
```

The destination must not exist. The command authenticates before extraction, checks the restored fingerprint, then validates torrc/includes in a disposable container with networking disabled. Omit `--validation-image` to use the original image ID if it is still available locally. Any failure removes only the newly created staging directory. As root, restore applies UID 100/GID 101; otherwise arrange ownership before activation.

| Restored path | Activation mapping |
| --- | --- |
| `relay-restored/data/` | Mount at the manifest's original DataDirectory |
| `relay-restored/config/etc/tor/torrc` | Mount at the original config path |
| Other `config/` files | Mount each include at its original absolute path |
| `deployment/` | Review against current ports, mounts and image |
| `logs/` | Retain as evidence; do not confuse it with current-run readiness |

Stop the old relay before activating the restored identity. Never run two relays with the same identity. Check ownership, validate the deployment, start deliberately, compare fingerprints, and examine fresh health and external reachability. Do not replace live data as part of verification.

## 🛡️ Recovery checklist

- Keep more than one encrypted copy, with at least one off-host copy.
- Protect decryption keys separately and test access to them.
- Verify each archive, and rehearse restore after configuration or image changes.
- Preserve the previous image digest and deployment as the rollback pair.
- Retain archives according to your own policy; the command does not delete old backups or install a scheduler.

[Operator tools](TOOLS.md) · [FAQ](FAQ.md)
