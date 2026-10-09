# 🔐 Backup & Recovery Guide - Tor Guard Relay

Complete instructions for backing up and restoring your Tor relay's identity, keys, and configuration data.

---

## Table of Contents

- [Why Backups Matter](#why-backups-matter)
- [What to Backup](#what-to-backup)
- [Backup Methods](#backup-methods)
- [Recovery Procedures](#recovery-procedures)
- [Migration Guide](#migration-guide)
- [Best Practices](#best-practices)

---

## Why Backups Matter

Your Tor relay's **identity is permanent**. Once established, it becomes part of the Tor network's fabric. Losing these keys means:

- 🚫 Loss of your relay's fingerprint
- 📉 Loss of reputation built over time
- 🔄 New relay starting from zero
- ⏰ 8+ days to regain guard flag

**Create and verify an encrypted complete recovery set after first successful bootstrap.**

---

## What to Backup

### 🔑 Critical Files (Preserve Forever)

Located in `/var/lib/tor/`:

| File | Purpose | Restore Impact |
|------|---------|-----------------|
| `keys/ed25519_master_id_secret_key` | Master identity key | **CRITICAL** - Defines relay identity |
| `keys/ed25519_signing_secret_key` | Signing key | **CRITICAL** - Signs all operations |
| `keys/secret_id_key` | RSA relay identity | **CRITICAL** - Preserve with Ed25519 identity |
| `keys/secret_onion_key` | Circuit handshake key | Preserve as part of the complete data directory |
| `keys/*.secret_family_key` | Happy Family key material | Preserve family continuity |
| `pt_state/` | Transport state and bridge certificate | Preserve bridge compatibility |
| `fingerprint` | Your relay fingerprint | Reference only (can regenerate) |

### 📋 Important Files (Backup Regularly)

| File | Purpose | Restore Impact |
|------|---------|-----------------|
| `cached-consensus` | Current Tor consensus | Nice to have (rebuilds automatically) |
| `cached-descriptors` | Relay descriptors | Nice to have (rebuilds automatically) |
| `state` | Relay state file | Optional (recreated on startup) |

### ⚙️ Configuration (Backup Before Changes)

| File | Location | Purpose |
|------|----------|---------|
| `relay.conf` | Host machine | Your relay configuration |
| `torrc` | `/etc/tor/torrc` (in container) | Mounted copy of relay.conf |

---

## Backup Methods

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

---

## Recovery Procedures

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


### 🐳 Scenario 1: Container corruption

If state remains intact, validate it with the recorded deployment and image before recreating. Stop the old writer; do not activate a restored copy concurrently. If restoring is necessary, use a new staging directory and compare the fingerprint before explicit activation.

### 🖥️ Scenario 2: Server failure

Recover the encrypted archive, compatible validation image and separately protected age identity. Verify before extraction, restore offline and review every config/include mapping on the replacement host. Prepare UID 100/GID 101 ownership, firewall and public addresses before deliberate activation.

### 🔑 Scenario 3: Key loss

Restore the complete identity/state set from a verified archive. A fingerprint text file is not a replacement for private identity keys. If private keys and usable backups are lost, the old identity cannot be recovered; do not claim a new key is the old relay.

---

## Migration Guide

### 🌍 Move a relay to a new server

1. Record fingerprint, image digest, config/include paths, deployment and public listeners.
2. Create and verify a complete encrypted backup, and separately preserve external master keys.
3. Transfer ciphertext and deployment through your approved channel; keep the decryption identity in separate custody.
4. Rehearse staged restore on the new host with networking disabled and compare fingerprints.
5. Stop the original relay before deliberately activating the restored identity.
6. Confirm fresh bootstrap, transport state and external reachability. Retain the old image/deployment for rollback.

### ⏱️ Downtime and identity safety

The built-in command stops writers for a consistent snapshot. Plan that short interruption; it does not promise zero downtime. Never run two relay instances sharing the same identity or data directory. See [migration](MIGRATION.md) for ownership and rollback details.

---

## Best Practices

### ✅ DO

- ✅ **Backup immediately after bootstrap** - Preserve identity
- ✅ **Use strong encryption** for off-site backups
- ✅ **Test restores regularly** - Backups are worthless if unverifiable
- ✅ **Document fingerprints** - Keep reference copy of fingerprint
- ✅ **Automate backups** - Set and forget with cron
- ✅ **Store backups securely** - Encrypt sensitive data
- ✅ **Keep multiple copies** - Local + off-site minimum
- ✅ **Version your backups** - Date-stamped directories

### ❌ DON'T

- ❌ **Don't backup `/etc/tor/torrc`** - Mount as read-only from host
- ❌ **Don't share backup media unencrypted** - Keys are sensitive
- ❌ **Don't rely on single backup** - 3-2-1 rule applies
- ❌ **Don't ignore backup failures** - Monitor logs
- ❌ **Don't delete old backups immediately** - Keep 30+ days

### 📊 3-2-1 Backup Rule

Maintain at minimum:

- **3 copies** of your data
  - Original (running relay)
  - Backup 1 (local storage)
  - Backup 2 (off-site)
- **2 different media types**
  - NVMe/SSD
  - USB external drive
- **1 off-site copy**
  - Cloud storage (encrypted)
  - Or remote server

---

## Troubleshooting

### 🛑 Backup refuses a running source

Use `--stop` for a controlled snapshot, or stop the source explicitly first. Other running containers sharing the storage must also be stopped. Docker cannot detect host processes writing a bind directory; stop those writers separately.

### 🔐 Decryption or integrity verification fails

Confirm the correct private age identity is available. A wrong identity, truncated ciphertext or tampered archive must fail closed; do not bypass verification. Retry from an independent encrypted copy.

### 📁 Restore destination exists or permissions are wrong

Choose a new staging path. Never overwrite live state. Prepare ownership on that newly restored directory for UID 100/GID 101 before activation; WSL Linux storage gives stronger Unix permission guarantees than Windows-mounted backup storage.

### 🆔 Fingerprint differs after restore

Stop before activation. Compare the encrypted manifest, restored fingerprint and complete private key set. Confirm mount paths and external master-key custody; do not erase the previous recovery material while investigating.

---

## Reference

**🔐 Encrypted recovery cheat sheet:**

```sh
# Preview encrypted coverage, then take a controlled snapshot.
sh scripts/utilities/relay-backup.sh create --container tor-relay \
  --recipients "$HOME/.config/relay-backup/recipients.txt" \
  --output-dir "$HOME/relay-backups" --dry-run
sh scripts/utilities/relay-backup.sh create --container tor-relay \
  --recipients "$HOME/.config/relay-backup/recipients.txt" \
  --output-dir "$HOME/relay-backups" --stop

# Replace BACKUP with the archive name printed by create.
sh scripts/utilities/relay-backup.sh verify "$HOME/relay-backups/BACKUP.tar.gz.age" \
  --identity "$HOME/.config/relay-backup/identity.txt"
sh scripts/utilities/relay-backup.sh restore "$HOME/relay-backups/BACKUP.tar.gz.age" \
  --identity "$HOME/.config/relay-backup/identity.txt" \
  --destination "$HOME/relay-restored" --validation-image tor-relay:2.2.0-local
```

🔐 Keep the private age identity separately. Restore only to a new staging directory, validate ownership and mounts, and stop the previous relay before activating its identity. The validation image must already exist locally.

---

## Support

- 📖 [Main README](../README.md)
- 🚀 [Deployment Guide](./DEPLOYMENT.md)
- 🐛 [Report Issues](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💬 [Tor Relay Forum](https://forum.torproject.org/)
