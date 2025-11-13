# 🔄 Multi-Mode Relay Guide - Tor Guard Relay

Complete guide to running Guard/Middle relays, Exit relays, and obfs4 Bridges.

---

## Table of Contents

- [Overview](#overview)
- [Mode Comparison](#mode-comparison)
- [Guard/Middle Relay Mode](#guardmiddle-relay-mode)
- [Exit Relay Mode](#exit-relay-mode)
- [obfs4 Bridge Mode](#obfs4-bridge-mode)
- [Configuration Methods](#configuration-methods)
- [Environment Variables Reference](#environment-variables-reference)
- [Switching Modes](#switching-modes)
- [Troubleshooting](#troubleshooting)

---

## Overview

The Tor Guard Relay container now supports **three relay modes**:

| Mode | Purpose | Public Visibility | Legal Risk | Bandwidth Needs |
|------|---------|------------------|------------|-----------------|
| **Guard/Middle** | Entry/routing relay | High | Low | Medium-High |
| **Exit** | Exit traffic to internet | High | **HIGH** | High |
| **Bridge** | Help censored users | Hidden | Low | Low-Medium |

### Key Features

- ✅ **Dynamic Configuration** - Generate config from environment variables
- ✅ **obfs4 Support** - Pluggable transport for bridges
- ✅ **Backwards Compatible** - Still supports mounting config files
- ✅ **Secure Defaults** - Guard/middle as default mode

---

## Mode Comparison

### Guard/Middle Relay (Default)

**What it does:**
- Acts as entry point (guard) or routing node (middle) in Tor circuits
- Does NOT handle exit traffic to the internet
- Published in the main Tor directory

**Best for:**
- Operators who want to contribute without legal complexity
- Stable, high-bandwidth connections
- Long-term operation (8+ days to earn Guard flag)

**Requirements:**
- Public IP with ports 9001, 9030 accessible
- Stable uptime (99%+ recommended)
- 10+ Mbps bandwidth recommended

### Exit Relay

**What it does:**
- Allows Tor traffic to exit to the internet
- Your IP is associated with all exit traffic
- Published in the main Tor directory

**Best for:**
- Experienced operators who understand legal implications
- Datacenters with abuse handling
- Dedicated servers/IPs

**⚠️ CRITICAL REQUIREMENTS:**
- **Understand legal risks** - read [EFF Tor Legal FAQ](https://community.torproject.org/relay/community-resources/eff-tor-legal-faq/)
- Prepare for abuse complaints
- Inform your ISP
- Set up abuse@ email address
- Have legal resources available
- Use dedicated IP/server

### obfs4 Bridge

**What it does:**
- Helps users in censored countries connect to Tor
- NOT published in main directory (distributed via BridgeDB)
- Uses obfs4 to make traffic look random

**Best for:**
- Operators in non-censored countries
- Lower bandwidth contributions
- Helping circumvent censorship

**Requirements:**
- Stable IP with ports 9001, 9002 accessible
- Less bandwidth than relays (10+ Mbps sufficient)
- Not blocked by censors in target countries

---

## Guard/Middle Relay Mode

### Quick Start with Environment Variables

```bash
docker run -d \
  --name tor-guard-relay \
  --network host \
  --restart unless-stopped \
  -e TOR_RELAY_MODE=guard \
  -e TOR_NICKNAME=MyGuardRelay \
  -e TOR_CONTACT_INFO="your-email@example.com" \
  -e TOR_BANDWIDTH_RATE="50 MBytes" \
  -e TOR_BANDWIDTH_BURST="100 MBytes" \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

### Docker Compose

```yaml
version: '3.8'

services:
  tor-guard-relay:
    image: ghcr.io/r3bo0tbx1/onion-relay:latest
    container_name: tor-guard-relay
    restart: unless-stopped
    network_mode: host
    environment:
      TOR_RELAY_MODE: guard
      TOR_NICKNAME: MyGuardRelay
      TOR_CONTACT_INFO: "your-email@example.com"
      TOR_BANDWIDTH_RATE: "50 MBytes"
      TOR_BANDWIDTH_BURST: "100 MBytes"
    volumes:
      - tor-guard-data:/var/lib/tor
      - tor-guard-logs:/var/log/tor

volumes:
  tor-guard-data:
  tor-guard-logs:
```

Save as `docker-compose.yml` and run:
```bash
docker-compose up -d
```

### Verification

```bash
# Check status
docker exec tor-guard-relay status

# View logs
docker logs -f tor-guard-relay

# Get fingerprint
docker exec tor-guard-relay fingerprint
```

---

## Exit Relay Mode

### ⚠️ Before You Start

**READ THIS FIRST:**
1. [EFF Tor Legal FAQ](https://community.torproject.org/relay/community-resources/eff-tor-legal-faq/)
2. [Tor Abuse Response Templates](https://community.torproject.org/relay/community-resources/tor-abuse-templates/)
3. [Good/Bad ISPs for Exit Relays](https://community.torproject.org/relay/community-resources/good-bad-isps/)

**Exit Relay Checklist:**
- [ ] Read and understand legal implications
- [ ] Prepared to handle abuse complaints
- [ ] Informed ISP (recommended)
- [ ] Set up abuse@ email address
- [ ] Using dedicated IP/server
- [ ] Have abuse response template ready
- [ ] Have legal resources available if needed

### Quick Start

```bash
docker run -d \
  --name tor-exit-relay \
  --network host \
  --restart unless-stopped \
  -e TOR_RELAY_MODE=exit \
  -e TOR_NICKNAME=MyExitRelay \
  -e TOR_CONTACT_INFO="your-email@example.com <0xPGP_KEY>" \
  -e TOR_BANDWIDTH_RATE="50 MBytes" \
  -e TOR_BANDWIDTH_BURST="100 MBytes" \
  -v tor-exit-data:/var/lib/tor \
  -v tor-exit-logs:/var/log/tor \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

### Exit Policy

By default, uses the **Reduced Exit Policy** (Tor Project recommended):
- Allows common services (HTTP, HTTPS, SSH, email, etc.)
- Blocks high-risk ports
- Good starting point for exit operators

**Custom Exit Policy:**
```bash
-e TOR_EXIT_POLICY="accept *:80,accept *:443,reject *:*"
```

**More restrictive (HTTPS only):**
```bash
-e TOR_EXIT_POLICY="accept *:443,reject *:*"
```

### Docker Compose

See [templates/docker-compose-exit.yml](../templates/docker-compose-exit.yml) for complete example.

### Handling Abuse Complaints

**Standard Response Template:**
```
This is a Tor exit relay (https://www.torproject.org/).
The IP address you reported is not the source of the activity.
Tor is an anonymity network that helps people protect their
privacy and security online.

For more information about Tor and exit relays:
- What is Tor: https://www.torproject.org/about/overview.html
- Tor and abuse: https://blog.torproject.org/blog/tips-running-exit-node

If you have concerns about specific traffic, please contact
the destination website directly. The exit relay operator
does not control the traffic passing through the relay.

Contact: your-email@example.com
```

---

## obfs4 Bridge Mode

### Quick Start

```bash
docker run -d \
  --name tor-bridge \
  --network host \
  --restart unless-stopped \
  -e TOR_RELAY_MODE=bridge \
  -e TOR_NICKNAME=MyTorBridge \
  -e TOR_CONTACT_INFO="your-email@example.com" \
  -e TOR_ORPORT=9001 \
  -e TOR_OBFS4_PORT=9002 \
  -e TOR_BANDWIDTH_RATE="10 MBytes" \
  -e TOR_BANDWIDTH_BURST="20 MBytes" \
  -v tor-bridge-data:/var/lib/tor \
  -v tor-bridge-logs:/var/log/tor \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

### Docker Compose

See [templates/docker-compose-bridge.yml](../templates/docker-compose-bridge.yml) for complete example.

### Getting Your Bridge Line

**After 24-48 hours**, your bridge will be registered and you can get the bridge line:

```bash
# Method 1: Check pt_state directory
docker exec tor-bridge cat /var/lib/tor/pt_state/obfs4_bridgeline.txt

# Method 2: Search logs
docker exec tor-bridge grep "bridge line" /var/log/tor/notices.log

# Method 3: Check pt_state directory contents
docker exec tor-bridge ls -la /var/lib/tor/pt_state/
```

Output will look like:
```
Bridge obfs4 <IP>:<PORT> <FINGERPRINT> cert=<CERT> iat-mode=0
```

### Sharing Your Bridge

**IMPORTANT:**
- Only share with people you trust
- Do NOT publish publicly (defeats the purpose)
- Users can also request bridges from [BridgeDB](https://bridges.torproject.org/)

### Verification

```bash
# Check if obfs4proxy is running
docker exec tor-bridge pgrep -a obfs4proxy

# Check bridge status
docker exec tor-bridge status
```

---

## Configuration Methods

The container supports **two configuration methods**:

### Method 1: Environment Variables (Recommended for Simple Setups)

**Pros:**
✓ No config file to maintain
✓ Easy to change settings
✓ Good for simple setups
✓ Works well with orchestration tools

**Cons:**
✗ Less flexible for advanced options
✗ Cannot set all possible Tor directives

**Example:**
```bash
docker run -d \
  -e TOR_RELAY_MODE=guard \
  -e TOR_NICKNAME=MyRelay \
  -e TOR_CONTACT_INFO="email@example.com" \
  ...
```

### Method 2: Config File Mount (Advanced)

**Pros:**
✓ Full control over Tor configuration
✓ Can use any Tor directive
✓ Better for complex setups

**Cons:**
✗ Need to maintain config file
✗ Less portable

**Example:**
```bash
docker run -d \
  -v $(pwd)/relay.conf:/etc/tor/torrc:ro \
  ...
```

### Can I Use Both?

Yes! If you mount a config file, it takes precedence over environment variables.
The container will detect the mounted file and skip dynamic config generation.

---

## Environment Variables Reference

### Core Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TOR_RELAY_MODE` | `guard` | Relay mode: `guard`, `exit`, or `bridge` |
| `TOR_NICKNAME` | _(required)_ | Relay nickname (1-19 alphanumeric chars) |
| `TOR_CONTACT_INFO` | _(required)_ | Contact email (+ optional PGP key) |

### Network Ports

| Variable | Default | Description |
|----------|---------|-------------|
| `TOR_ORPORT` | `9001` | Tor connection port |
| `TOR_DIRPORT` | `9030` | Directory service port (not used for bridges) |
| `TOR_OBFS4_PORT` | `9002` | obfs4 pluggable transport port (bridges only) |

### Bandwidth

| Variable | Default | Description |
|----------|---------|-------------|
| `TOR_BANDWIDTH_RATE` | _(none)_ | Sustained bandwidth (e.g., `50 MBytes`) |
| `TOR_BANDWIDTH_BURST` | _(none)_ | Burst bandwidth (e.g., `100 MBytes`) |

### Exit Policy (Exit Mode Only)

| Variable | Default | Description |
|----------|---------|-------------|
| `TOR_EXIT_POLICY` | Reduced Exit Policy | Custom exit policy (comma-separated) |

Example: `TOR_EXIT_POLICY="accept *:80,accept *:443,reject *:*"`

### Advanced

| Variable | Default | Description |
|----------|---------|-------------|
| `TOR_DATA_DIR` | `/var/lib/tor` | Tor data directory |
| `TOR_LOG_DIR` | `/var/log/tor` | Tor log directory |
| `TOR_CONFIG` | `/etc/tor/torrc` | Tor configuration file path |
| `DEBUG` | `false` | Enable debug output |

---

## Switching Modes

You can switch between modes by changing `TOR_RELAY_MODE` and restarting:

### From Guard to Exit

```bash
docker stop tor-relay
docker rm tor-relay

docker run -d \
  --name tor-relay \
  -e TOR_RELAY_MODE=exit \
  -e TOR_NICKNAME=MyExitRelay \
  ...  # Same volumes
```

**⚠️ WARNING:** Switching to exit mode has legal implications. Read the Exit Relay section first.

### From Guard to Bridge

```bash
docker stop tor-relay
docker rm tor-relay

docker run -d \
  --name tor-relay \
  -e TOR_RELAY_MODE=bridge \
  -e TOR_NICKNAME=MyBridge \
  -e TOR_OBFS4_PORT=9002 \
  ...  # Same volumes
```

**Note:** Your relay will get a new identity when switching modes.

---

## Troubleshooting

### Configuration Not Generating

**Symptom:** Container starts but uses placeholder config

**Solution:**
1. Make sure no config file is mounted at `/etc/tor/torrc`
2. Set required environment variables:
   - `TOR_NICKNAME`
   - `TOR_CONTACT_INFO`
3. Check logs: `docker logs <container>`

### Bridge Line Not Appearing

**Symptom:** Bridge line file doesn't exist after 24+ hours

**Solution:**
1. Check both ports are accessible: `9001` and `9002`
2. Verify obfs4proxy is running: `docker exec <container> pgrep obfs4proxy`
3. Check logs for obfs4proxy errors: `docker logs <container> | grep obfs4`
4. Wait 48 hours - bridge distribution takes time

### Exit Relay - Too Many Abuse Complaints

**Symptom:** Receiving excessive abuse complaints

**Solutions:**
1. Switch to more restrictive exit policy (HTTPS only)
2. Consider running as guard relay instead
3. Check if your ISP supports exit relays: [Good/Bad ISPs](https://community.torproject.org/relay/community-resources/good-bad-isps/)
4. Use abuse complaint template to respond efficiently

### Ports Not Accessible

**Symptom:** `ORPort not reachable` in status

**Solution:**
```bash
# Check firewall
sudo ufw status

# Open required ports
sudo ufw allow 9001/tcp
sudo ufw allow 9030/tcp  # Guards/exits only
sudo ufw allow 9002/tcp  # Bridges only

# Test from outside
nc -zv <your-ip> 9001
```

### Low/No Traffic

**Symptom:** Relay shows very little bandwidth usage

**Normal for:**
- New relays (2-8 weeks to build reputation)
- Bridges (intentionally low visibility)
- Guards without Guard flag (need 8+ days uptime)

**Check:**
1. Verify relay is reachable: `docker exec <container> status`
2. Check Tor Metrics: https://metrics.torproject.org/rs.html
3. Ensure adequate bandwidth: `TOR_BANDWIDTH_RATE`

---

## Resources

### Official Tor Project

- [Relay Setup Guide](https://community.torproject.org/relay/setup/)
- [Bridge Setup Guide](https://community.torproject.org/relay/setup/bridge/)
- [Relay Requirements](https://community.torproject.org/relay/relays-requirements/)
- [Tor Metrics](https://metrics.torproject.org/)
- [BridgeDB](https://bridges.torproject.org/)

### Legal & Compliance

- [EFF Tor Legal FAQ](https://community.torproject.org/relay/community-resources/eff-tor-legal-faq/)
- [Abuse Response Templates](https://community.torproject.org/relay/community-resources/tor-abuse-templates/)
- [Good/Bad ISPs](https://community.torproject.org/relay/community-resources/good-bad-isps/)

### Technical Documentation

- [obfs4 Specification](https://gitlab.com/yawning/obfs4)
- [Tor Manual](https://2019.www.torproject.org/docs/tor-manual.html.en)

### This Project

- [Main README](../README.md)
- [Deployment Guide](DEPLOYMENT.md)
- [Tools Documentation](TOOLS.md)
- [Monitoring Guide](MONITORING.md)

---

**Made with 💜 for a freer, uncensored internet**

*Protecting privacy, one relay at a time* 🧅✨
