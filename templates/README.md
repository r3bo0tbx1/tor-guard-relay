# Tor Relay Templates Guide

This directory contains deployment templates for running Tor relays in **3 modes**: Guard/Middle, Exit, and Bridge (obfs4).

## 📁  Template Files Overview

### [Cosmos Cloud Templates (JSON)](/templates/cosmos-compose/)

| File | Mode | ENV Naming | Use Case |
|------|------|------------|----------|
| `cosmos-compose-guard.json` | Guard/Middle | TOR_* | Standard guard relay, ENV-based config |
| `cosmos-compose-exit.json` | Exit | TOR_* | Exit relay with reduced policy, ENV-based config |
| `cosmos-compose-bridge.json` | Bridge (obfs4) | TOR_* | Bridge relay, ENV-based config |
| `cosmos-compose-bridge-official.json` | Bridge (obfs4) | OR_PORT, PT_PORT, EMAIL | **Drop-in replacement for thetorproject/obfs4-bridge** |
| `cosmos-compose-multi-relay.json` | All 3 modes | TOR_* | Run guard, exit, and bridge simultaneously |
| `cosmos-bind-config-guard-relay.json` | Guard/Middle | TOR_* | Standard guard relay, mounted config |
| `cosmos-bind-config-bridge.json` | Bridge (obfs4) | TOR_* | Bridge relay, mounted config |

### [Docker Compose Templates (YAML)](/templates/docker-compose/)

| File | Mode | ENV Naming | Use Case |
|------|------|------------|----------|
| `docker-compose-guard-env.yml` | Guard/Middle | TOR_* | Standard Docker Compose guard relay |
| `docker-compose-exit.yml` | Exit | TOR_* | Standard Docker Compose exit relay |
| `docker-compose-bridge.yml` | Bridge (obfs4) | TOR_* | Standard Docker Compose bridge |
| `docker-compose-bridge-official.yml` | Bridge (obfs4) | OR_PORT, PT_PORT, EMAIL | **Drop-in replacement for thetorproject/obfs4-bridge** |
| `docker-compose-multi-relay.yml` | All 3 modes | TOR_* | Run multiple relay modes |

## 🔧 Configuration Methods

You can configure Tor relays using **TWO methods**:

### Method 1: Environment Variables (Recommended for Simple Setups)

**Pros:**
- ✅ No config file needed
- ✅ Easy to customize via Cosmos/Portainer/docker-compose
- ✅ Simple deployment

**Cons:**
- ❌ Limited to basic options
- ❌ Can't use all advanced Tor features

**Example (Bridge):**
```bash
docker run -d \
  --name tor-bridge \
  --network host \
  --security-opt no-new-privileges:true \  
  -e TOR_RELAY_MODE=bridge \
  -e TOR_NICKNAME=MyBridge \
  -e TOR_CONTACT_INFO=admin@example.com \
  -e TOR_ORPORT=9001 \
  -e TOR_OBFS4_PORT=9002 \
  -v tor-data:/var/lib/tor \
  r3bo0tbx1/onion-relay:latest
```

**All available ENV variables:**
```bash
# Core (required for ENV-based config)
TOR_RELAY_MODE=guard|exit|bridge   # Relay mode
TOR_NICKNAME=MyRelay                # Relay nickname (1-19 chars, alphanumeric)
TOR_CONTACT_INFO=admin@example.com  # Contact email

# Ports (configurable)
TOR_ORPORT=9001         # ORPort for relay traffic (default: 9001)
TOR_DIRPORT=9030        # DirPort for guard/exit only (default: 9030, set to 0 to disable)
TOR_OBFS4_PORT=9002     # obfs4 port for bridge mode (default: 9002)

# Bandwidth (optional)
TOR_BANDWIDTH_RATE=50 MBytes
TOR_BANDWIDTH_BURST=100 MBytes

# Exit policy (exit mode only, optional)
TOR_EXIT_POLICY=accept *:80,accept *:443,reject *:*
```

### Method 2: Mounted Config File (Advanced Configurations)

**Pros:**
- ✅ Full access to all Tor configuration options
- ✅ Can use complex exit policies, custom options, etc.
- ✅ Better for production deployments

**Cons:**
- ❌ Requires creating and maintaining a torrc file
- ❌ Slightly more complex

**Example (Bridge with mounted config):**
```bash
docker run -d \
  --name tor-bridge \
  --network host \
  --security-opt no-new-privileges:true \  
  -v /path/to/relay-bridge.conf:/etc/tor/torrc:ro \
  -v tor-data:/var/lib/tor \
  r3bo0tbx1/onion-relay:latest
```

**Cosmos Cloud JSON (remove environment, add bind mount):**
```json
{
  "volumes": [
    {
      "type": "bind",
      "source": "/path/to/relay-bridge.conf",
      "target": "/etc/tor/torrc",
      "read_only": true
    },
    {
      "type": "volume",
      "source": "tor-bridge-data",
      "target": "/var/lib/tor"
    }
  ]
}
```

**Config file examples:** See `examples/relay-guard.conf`, `examples/relay-exit.conf`, `examples/relay-bridge.conf`

## 🌉 Bridge Mode: Two ENV Naming Conventions

We support **BOTH** naming conventions for maximum compatibility:

### TOR_* Naming (Our Standard)
```bash
TOR_RELAY_MODE=bridge
TOR_NICKNAME=MyBridge
TOR_CONTACT_INFO=admin@example.com
TOR_ORPORT=9001
TOR_OBFS4_PORT=9002
```

### Official Tor Project Naming (Drop-in Compatibility)
```bash
# These map to TOR_* internally:
NICKNAME=MyBridge           # → TOR_NICKNAME
EMAIL=admin@example.com     # → TOR_CONTACT_INFO
OR_PORT=9001                # → TOR_ORPORT
PT_PORT=9002                # → TOR_OBFS4_PORT
```

**Auto-detection:** Setting `PT_PORT` automatically sets `TOR_RELAY_MODE=bridge`.

### Advanced Bridge Options (OBFS4V_* Variables)

For advanced torrc options (like `AddressDisableIPv6`, `MaxMemInQueues`, etc.):

1. **Enable processing:**
   ```bash
   OBFS4_ENABLE_ADDITIONAL_VARIABLES=1
   ```

2. **Add OBFS4V_* variables** (mapped to torrc options):
   ```bash
   OBFS4V_AddressDisableIPv6=0
   OBFS4V_MaxMemInQueues=1024 MB
   OBFS4V_NumCPUs=4
   ```

3. **Whitelist:** Only specific torrc options are allowed (security):
   - `AddressDisableIPv6`
   - `MaxMemInQueues`
   - `NumCPUs`
   - `BandwidthRate`, `BandwidthBurst`
   - `AccountingMax`, `AccountingStart`
   - And other safe options (see `docker-entrypoint.sh` line 318-332)

4. **For options NOT in whitelist:** Use a mounted config file instead.

## 🔍 Common Questions

### Q: Why are there 2 bridge templates?

**A:** For compatibility and flexibility:
- `cosmos-compose-bridge.json` - Uses TOR_* naming (our standard)
- `cosmos-compose-bridge-official.json` - Uses OR_PORT/PT_PORT/EMAIL naming (drop-in replacement for `thetorproject/obfs4-bridge`)

Both work identically, choose based on your preference or migration needs.

### Q: Why is TOR_DIRPORT set in Dockerfile when bridges don't use it?

**A:** TOR_DIRPORT=9030 is a **Dockerfile default** for guard/exit modes. The entrypoint **DOES NOT** add DirPort to bridge configurations (see `docker-entrypoint.sh` lines 276-290). Bridges only use ORPort and obfs4 port.

**Port usage by mode:**
- **Guard/Middle:** TOR_ORPORT (required), TOR_DIRPORT (optional, set to 0 to disable)
- **Exit:** TOR_ORPORT (required), TOR_DIRPORT (optional)
- **Bridge:** TOR_ORPORT (required), TOR_OBFS4_PORT (required), TOR_DIRPORT (ignored/not used)

### Q: Why does TOR_RELAY_MODE say "guard" in logs when I set PT_PORT?

**A:** This shouldn't happen anymore (v1.1.1+). The entrypoint auto-detects bridge mode when `PT_PORT` is set (lines 29-31):

```sh
if [ -n "${PT_PORT:-}" ] && [ "${TOR_RELAY_MODE:-guard}" = "guard" ]; then
  TOR_RELAY_MODE="bridge"
fi
```

If you see "guard" mode in bridge deployment:
1. Verify you're using v1.1.1+ image: `docker exec <container> cat /build-info.txt`
2. Check container is actually running the new image: `docker inspect <container> --format='{{.Image}}'`
3. Recreate container (don't just restart): `docker rm -f <container> && docker run ...`

### Q: What's the difference between `{ "driver": "local" }` and `{}` for volumes?

**A:** They're **identical**. Both create a local named volume:
- `"tor-data": {}` - Minimal syntax (default driver is "local")
- `"tor-data": { "driver": "local" }` - Explicit syntax (redundant but clear)

We use `{}` in templates (simpler), but both work the same.

### Q: OBFS4V_* variables are being skipped with "dangerous characters" error?

**A:** This was a bug in v1.1.0 and earlier (busybox grep regex issue). **Fixed in v1.1.1+**.

The entrypoint now properly validates values:
- Rejects actual newlines (not escaped \n)
- Rejects null bytes and control characters
- Allows spaces (e.g., "1024 MB")

If you still see this error after updating to v1.1.1:
1. Check image version: `docker exec <container> cat /build-info.txt`
2. Verify value doesn't have real newlines (JSON array formatting shouldn't cause this)
3. Try using a mounted config file for complex options

### Q: Should I use ENV variables or mounted config file?

**A:** Use this decision tree:

**Use ENV variables if:**
- ✅ Running a simple guard/middle/bridge relay
- ✅ Standard port configuration
- ✅ Basic bandwidth limits
- ✅ Easy deployment is priority

**Use mounted config file if:**
- ✅ Complex exit policies
- ✅ Advanced Tor options not in OBFS4V_* whitelist
- ✅ Multiple ORPort addresses (IPv4 + IPv6)
- ✅ Accounting limits with specific start times
- ✅ Production deployment requiring full control

**You can also mix:** Start with ENV variables, then migrate to mounted config later without losing your relay identity (keys in `/var/lib/tor` are preserved).

## 🚀 Quick Start Examples

### Guard Relay (Cosmos Cloud)
1. Import `cosmos-compose-guard.json`
2. Change: TOR_NICKNAME, TOR_CONTACT_INFO
3. Deploy
4. Check: `docker exec tor-guard-relay status`

### Bridge (Drop-in Official Replacement)
1. Import `cosmos-compose-bridge-official.json`
2. Change: NICKNAME, EMAIL
3. Deploy
4. Get bridge line: `docker exec obfs4-bridge bridge-line`

### Exit Relay (Docker Compose)
1. Copy `docker-compose-exit.yml`
2. Edit ENV variables (nickname, contact, bandwidth)
3. **READ docs/LEGAL.md first!**
4. Run: `docker-compose up -d`

## 📚 Additional Resources

- **Full deployment guide:** `docs/DEPLOYMENT.md`
- **Example config files:** `examples/relay-*.conf`
- **Monitoring:** `docs/MONITORING.md`
- **Legal considerations (exit relays):** `docs/LEGAL.md`
- **Project instructions:** `CLAUDE.md`

## 🆘 Troubleshooting

### Container restarts immediately
- Check logs: `docker logs <container>`
- Verify ENV variables are set correctly (TOR_NICKNAME and TOR_CONTACT_INFO required for ENV-based config)
- Ensure volume permissions are correct

### Bridge mode detected as guard
- Update to v1.1.1+
- Recreate container (don't restart old one)
- Use `PT_PORT` for auto-detection or explicitly set `TOR_RELAY_MODE=bridge`

### OBFS4V_* variables ignored
- Update to v1.1.1+ (fixed parsing bug)
- Enable: `OBFS4_ENABLE_ADDITIONAL_VARIABLES=1`
- Check whitelist in `docker-entrypoint.sh` line 318-332
- Use mounted config for non-whitelisted options

### Ports not binding
- Verify `--network host` is set (required for IPv6)
- Check firewall rules
- Ensure ports aren't already in use: `ss -tlnp | grep <port>`

---

**Version:** 1.1.3
**Last Updated:** 2025-12-06
**Maintainer:** rE-Bo0t.bx1 <r3bo0tbx1@brokenbotnet.com>
