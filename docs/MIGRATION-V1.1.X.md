# 📜 Historical migration: v1.1.0 to v1.1.1

[Documentation](README.md) · [Current migration](MIGRATION.md) · [Encrypted recovery](BACKUP.md)

This record preserves the context of the earlier v1.1.x migration. Use the current guides for operating commands; old plaintext archive and live-volume repair examples are retired.

## ✨ Changes recorded in v1.1.1

The earlier release tightened OBFS4V input validation, ENV health checks, privilege handling, temporary-file handling and workflow permissions. It also corrected contact-info validation and bridge configuration.

## 🛡️ Mounted guard/middle deployments

Earlier guard/middle deployments with persistent data and a mounted torrc could keep their identity through image recreation. The essential checks remain: preserve keys, validate configuration, retain mounts, and compare fingerprints after recreation. A historic successful migration is not evidence that today's untested deployment will succeed.

## 🌉 Official bridge deployments

The earlier Debian image used UID 101 while this Alpine image uses UID 100/GID 101. That mismatch caused data-directory permission failures when volumes were reused without preparing ownership.

The earlier migration also encountered old torrc files remaining in volumes, and configurations pointing at a different data path. Those are configuration and storage ownership problems; deleting identity keys is never the repair.

## 🧭 Procedure today

Follow [Migration](MIGRATION.md). Create and verify an encrypted archive, rehearse staged offline restoration, stop every writer, then update ownership or deployment deliberately. Preserve family material and pt_state with the keys. Record the original image and ownership for rollback.
