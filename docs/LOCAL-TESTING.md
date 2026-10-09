# 🧪 Local Testing

[Documentation](README.md) · [Contributing](../CONTRIBUTING.md) · [Release process](../scripts/release/README.md)

Use isolated containers with synthetic identities. The acceptance suite runs with Docker networking disabled and publishes no relay descriptor.

## Environment

Docker Desktop on Windows with WSL works. Run host scripts in Linux/WSL with Python 3.10+, age, ShellCheck and dos2unix. A Linux Docker daemon is also supported. ARM64 testing on an AMD64 machine requires registered QEMU/binfmt support.

## 🔎 Source checks

```sh
python3 scripts/release/check-versions.py
python3 scripts/testing/check-templates.py
python3 scripts/testing/check-docs.py
shellcheck -S warning -x docker-entrypoint.sh healthcheck.sh lib/*.sh tools/* scripts/utilities/relay-backup.sh scripts/utilities/relay-inventory.sh
python3 -m unittest discover -s tests -v
git diff --check
```

Archive tests require age on PATH. A skipped archive test is not a recovery pass. Check LF line endings with dos2unix before building on Windows.

## 🏗️ Build and inspect candidates

```sh
docker buildx build --platform linux/amd64 --load \
  --build-arg BUILD_VERSION=2.2.0-local -t tor-relay:2.2.0-local .
python3 scripts/testing/image-acceptance.py tor-relay:2.2.0-local
python3 scripts/testing/check-image.py tor-relay:2.2.0-local
```

Repeat with `Dockerfile.edge` and both `linux/amd64` and `linux/arm64`. Pass the platform explicitly to image acceptance for ARM64. Check-image reads the Go dependency metadata from the actual transport binary as well as Tor and installed OpenSSL packages.

Acceptance covers guard, exit and bridge generation, custom torrc path, accounting, config validation, PID-preserving reload, fresh restart evidence, bridge transport state and clean shutdown. Injected bootstrap messages test observation logic; they are not proof of live bootstrap.

## 🔐 Recovery rehearsal

Follow [Backup](BACKUP.md) using a synthetic source. Create → verify → restore must preserve the fingerprint and pass offline Tor configuration validation. Rehearse named-volume and bind-mount layouts with includes when those match your deployment.

The archive regression suite checks wrong identities, truncation, unsafe paths, links, duplicate entries, mismatched hashes and refusal to overwrite an existing restore destination. Failure-path checks should also confirm that a stopped source stays stopped and a source stopped by create is restarted.

Run the isolated named-volume and bind-mount rehearsal with a task-owned scratch parent accessible to Docker:

```sh
python3 scripts/testing/recovery-rehearsal.py --image tor-relay:2.2.0-local --bind-parent /path/to/scratch
```

## 🎨 Presentation checks

Check every local Markdown link and image with the docs checker. Review the README and curated notes rendered on desktop and mobile. Run the separate website's Hugo build, security audit and tests before including an article in a publication handoff.
