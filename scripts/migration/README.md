# 🔄 Migration Assistant

[Current migration](../../docs/MIGRATION.md) · [Encrypted recovery](../../docs/BACKUP.md) · [Documentation](../../docs/README.md)

The interactive assistant helps identify an official bridge deployment, prepare Alpine UID 100/GID 101 ownership, recreate it and compare fingerprints. It is an operator-run mutation tool; local offline testing does not establish a production migration.

## 🔐 Required recovery setup

Install host Python 3.10+ and age. Prepare public recipient and private recovery identity files as described in the backup guide, then export their paths:

```sh
export RELAY_BACKUP_RECIPIENTS="$HOME/.config/relay-backup/recipients.txt"
export RELAY_BACKUP_IDENTITY="$HOME/.config/relay-backup/identity.txt"
sh scripts/migration/migrate-from-official.sh
```

These variables hold file paths, never passphrases. The assistant creates and fully verifies an encrypted backup of the detected source container before changing data. Backup failure aborts migration. It no longer creates a plaintext tar archive or offers to proceed without verification.

For a source without a detectable container or a supported config/include layout, follow manual staged recovery in the current migration guide. Do not guess a data path from unrelated volumes.

## ✅ Before and after

Record image digest, deployment, fingerprint, ownership, family material and bridge transport state. Inspect listener and mount choices before accepting the assistant's prompts.

After recreation, verify the same fingerprint, valid active torrc, current Tor version, fresh bootstrap and independent public reachability. Obtain a bridge line with an explicit public address. Retain the old deployment and encrypted backup for rollback, and never run duplicate identities.

The old `migration-validator.sh`, emergency torrc-deletion script and v1.1.x migration test are retired with clear successor instructions. Use health/doctor, host inventory and the isolated encrypted recovery rehearsal instead.
