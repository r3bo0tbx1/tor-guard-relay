# 🚀 Deployment Guide - Tor Guard Relay

Complete deployment instructions for guard, exit, and bridge relays across various hosting environments.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Method 1: Docker CLI](#method-1-docker-cli)
- [Method 2: Docker Compose](#method-2-docker-compose)
- [Method 3: Cosmos Cloud](#method-3-cosmos-cloud)
- [Method 4: Portainer](#method-4-portainer)
- [Multi-Mode Deployment](#multi-mode-deployment)
- [ENV-Based Deployment](#env-based-deployment)
- [Post-Deployment Verification](#post-deployment-verification)
- [Firewall Configuration](#firewall-configuration)
- [Hosting Provider Recommendations](#hosting-provider-recommendations)

---

## Prerequisites

Before deploying, ensure you have:

- ✅ **Docker** 20.10+ installed ([Install Docker](https://docs.docker.com/get-docker/))
- ✅ **Root or sudo access** on your server
- ✅ **Static public IP address**
- ✅ **Sufficient bandwidth** (10+ Mbps recommended)
- ✅ **Open firewall ports** (9001/tcp minimum, 9030/tcp recommended for guard/exit, 9002/tcp for bridges)
- ✅ **Prepared configuration** (config file OR environment variables)

---

## Method 1: Docker CLI

Perfect for quick deployments and testing.

### Step 1: Prepare Your Configuration

Create `relay.conf` file:

```bash
# Create config directory
mkdir -p ~/tor-relay
cd ~/tor-relay

# Download example config (guard relay)
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/examples/relay-guard.conf

# Edit configuration
nano relay-guard.conf
```

**Minimum required edits:**
- `Nickname` - Your relay name
- `ContactInfo` - Your email
- `ORPort` - Usually 9001 or 443
- `RelayBandwidthRate` - Your bandwidth limit

### Step 2: Pull the Image

```bash
# From GitHub Container Registry (recommended)
docker pull ghcr.io/r3bo0tbx1/onion-relay:latest

# Or from Docker Hub
docker pull r3bo0tbx1/onion-relay:latest
```

### Step 3: Run the Container

```bash
docker run -d \
  --name tor-relay \
  --network host \
  --security-opt no-new-privileges:true \
  -v ~/tor-relay/relay-guard.conf:/etc/tor/torrc:ro \
  -v tor-data:/var/lib/tor \
  -v tor-logs:/var/log/tor \
  --restart unless-stopped \
  r3bo0tbx1/onion-relay:latest
```

### Step 4: Verify Deployment

```bash
# Check container is running
docker ps | grep tor-relay

# Check logs and bootstrap progress
docker logs -f tor-relay

# Run diagnostics (5 tools available)
docker exec tor-relay status         # Full health report with emojis
docker exec tor-relay health         # JSON health data
docker exec tor-relay fingerprint    # Show fingerprint + Tor Metrics URL
```

---

## Method 2: Docker Compose

Best for reproducible deployments and version control.

### Step 1: Create Project Directory

```bash
mkdir -p ~/tor-relay
cd ~/tor-relay
```

### Step 2: Download Files

```bash
# Download docker-compose.yml (guard relay with mounted config)
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/templates/docker-compose.yml

# Download example config
curl -o relay.conf https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/examples/relay-guard.conf
```

### Step 3: Edit Configuration

```bash
nano relay.conf
```

Edit at minimum:
- `Nickname`
- `ContactInfo`
- `RelayBandwidthRate`

### Step 4: Deploy

```bash
# Start the relay
docker-compose up -d

# View logs
docker-compose logs -f

# Check status
docker-compose exec tor-relay status
```

### Step 5: Manage Deployment

```bash
# Stop relay
docker-compose down

# Restart relay
docker-compose restart

# Update to latest version
docker-compose pull
docker-compose up -d

# View resource usage
docker-compose stats
```

---

## Method 3: Cosmos Cloud

Perfect for users with [Cosmos Cloud](https://cosmos-cloud.io/) - a modern Docker management interface.

> **About Cosmos Cloud**: Created by [azukaar](https://github.com/azukaar), Cosmos Cloud is a self-hosted platform for managing Docker containers with a beautiful UI, automatic HTTPS, integrated auth, and smart automation features.
>
> - 🌐 **Website**: https://cosmos-cloud.io/
> - 📦 **GitHub**: https://github.com/azukaar/Cosmos-Server
> - 📖 **Docs**: https://cosmos-cloud.io/doc

### Prerequisites

- Cosmos Cloud installed and running ([Installation Guide](https://cosmos-cloud.io/doc/install))
- SSH access to your server

### Step 1: Prepare Configuration File

SSH into your server and create the relay configuration:

```bash
# Create config directory
sudo mkdir -p /opt/tor-relay

# Create and edit configuration
sudo nano /opt/tor-relay/relay.conf
```

Paste your relay configuration (see [example config](../examples/relay-guard.conf)).

**Important**: Edit at minimum:
- `Nickname` - Your relay name
- `ContactInfo` - Your email
- `RelayBandwidthRate` - Your bandwidth limit

Save and set permissions:
```bash
sudo chmod 600 /opt/tor-relay/relay.conf
```

### Step 2: Import Stack to Cosmos

1. Open your Cosmos Cloud UI (typically `https://your-server:443`)
2. Navigate to **ServApps** → **Import Compose File**
3. Download our Cosmos configuration:
   ```bash
   curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/templates/cosmos-compose-guard.json
   ```
4. Upload or paste the JSON content
5. **Optional**: Edit timezone if needed (default: `UTC`)
   ```json
   "TZ=UTC"              // Universal (default)
   "TZ=America/New_York"  // US East Coast
   "TZ=Europe/London"     // UK
   "TZ=Asia/Tokyo"        // Japan
   ```

### Step 3: Deploy

1. Review the configuration
2. Click **Create**
3. Wait for container to start
4. Navigate to **ServApps** → **TorRelay**
5. Click **Logs** to monitor bootstrap progress

### Step 4: Verify Deployment

From Cosmos UI, click **Console** (or use SSH):

```bash
docker exec tor-relay status
```

Look for:
- ✅ `Bootstrapped 100% (done): Done`
- ✅ `ORPort is reachable from the outside`

### Why Host Network Mode?

The Cosmos configuration uses `network_mode: host` instead of bridge networking. Here's why:

| Aspect | Host Mode | Bridge Mode |
|--------|-----------|-------------|
| **IPv6 Support** | ✅ Native dual-stack | ⚠️ Requires complex setup |
| **Port Forwarding** | ✅ Direct binding | ❌ Requires manual mapping |
| **Performance** | ✅ No NAT overhead | ⚠️ Slight latency |
| **Tor Compatibility** | ✅ Recommended by Tor Project | ⚠️ Can cause issues |

**TL;DR**: Host mode ensures your relay can bind to both IPv4 and IPv6 addresses directly, which is crucial for maximum Tor network participation.

### Auto-Update Feature

The stack includes automatic updates:
```json
"cosmos-auto-update": "true",
"cosmos-auto-update-notify": "true",
"cosmos-auto-update-restart": "true"
```

Cosmos will:
- 🔄 Check for new image versions weekly
- 📧 Notify you when updates are available
- 🔁 Automatically restart with new version

---

## Method 4: Portainer

Great for GUI-based management.

### Step 1: Access Portainer

Navigate to your Portainer instance (usually `https://your-server:9443`)

### Step 2: Create Stack

1. Click **Stacks** → **Add Stack**
2. Name it: `tor-relay`
3. Choose **Web editor**

### Step 3: Paste Stack Definition

```yaml
version: '3.8'

services:
  tor-relay:
    image: r3bo0tbx1/onion-relay:latest
    container_name: tor-relay
    restart: unless-stopped
    network_mode: host
    volumes:
      - /opt/tor-relay/relay.conf:/etc/tor/torrc:ro
      - tor-data:/var/lib/tor
      - tor-logs:/var/log/tor

volumes:
  tor-data:
  tor-logs:
```

### Step 4: Upload Configuration

1. SSH to your server and create config:
   ```bash
   sudo mkdir -p /opt/tor-relay
   sudo nano /opt/tor-relay/relay.conf
   ```
2. Paste your relay configuration and save

### Step 5: Deploy

1. Click **Deploy the stack**
2. Navigate to **Containers** → `tor-relay`
3. Click **Logs** to monitor
4. Click **Console** → Connect to run diagnostics:
   ```bash
   status
   health
   fingerprint
   ```

---

## Multi-Mode Deployment

This image supports **guard**, **exit**, and **bridge** relays in a single container.

### Guard/Middle Relay (Default)

```bash
# With mounted config
docker run -d \
  --name tor-guard \
  --network host \
  -v ~/relay-guard.conf:/etc/tor/torrc:ro \
  -v tor-data:/var/lib/tor \
  r3bo0tbx1/onion-relay:latest

# With ENV variables
docker run -d \
  --name tor-guard \
  --network host \
  -e TOR_RELAY_MODE=guard \
  -e TOR_NICKNAME=MyGuardRelay \
  -e TOR_CONTACT_INFO=tor@example.com \
  -e TOR_ORPORT=9001 \
  -v tor-data:/var/lib/tor \
  r3bo0tbx1/onion-relay:latest
```

### Exit Relay

```bash
# With mounted config (recommended for exits)
docker run -d \
  --name tor-exit \
  --network host \
  -v ~/relay-exit.conf:/etc/tor/torrc:ro \
  -v tor-data:/var/lib/tor \
  r3bo0tbx1/onion-relay:latest

# With ENV variables
docker run -d \
  --name tor-exit \
  --network host \
  -e TOR_RELAY_MODE=exit \
  -e TOR_NICKNAME=MyExitRelay \
  -e TOR_CONTACT_INFO=tor@example.com \
  -e TOR_ORPORT=9001 \
  -e TOR_EXIT_POLICY="accept *:80,accept *:443,reject *:*" \
  -v tor-data:/var/lib/tor \
  r3bo0tbx1/onion-relay:latest
```

### Bridge Relay (obfs4)

```bash
# With mounted config
docker run -d \
  --name tor-bridge \
  --network host \
  -v ~/relay-bridge.conf:/etc/tor/torrc:ro \
  -v tor-data:/var/lib/tor \
  r3bo0tbx1/onion-relay:latest

# With ENV variables
docker run -d \
  --name tor-bridge \
  --network host \
  -e TOR_RELAY_MODE=bridge \
  -e TOR_NICKNAME=MyBridge \
  -e TOR_CONTACT_INFO=tor@example.com \
  -e TOR_ORPORT=9001 \
  -e TOR_OBFS4_PORT=9002 \
  -v tor-data:/var/lib/tor \
  r3bo0tbx1/onion-relay:latest

# Get bridge line for sharing
docker exec tor-bridge bridge-line
```

**Templates:**
- Guard: [docker-compose-guard-env.yml](../templates/docker-compose-guard-env.yml)
- Exit: [docker-compose-exit.yml](../templates/docker-compose-exit.yml)
- Bridge: [docker-compose-bridge.yml](../templates/docker-compose-bridge.yml)

---

## ENV-Based Deployment

Full configuration via environment variables is supported (no config file needed).

### Supported Environment Variables

#### Core Configuration
- `TOR_RELAY_MODE` - guard, exit, or bridge (default: guard)
- `TOR_NICKNAME` - Relay nickname (required for ENV config)
- `TOR_CONTACT_INFO` - Contact email (required for ENV config)
- `TOR_ORPORT` - ORPort (default: 9001)
- `TOR_DIRPORT` - DirPort for guard/exit (default: 0 - disabled)
- `TOR_OBFS4_PORT` - obfs4 port for bridge mode (default: 9002)

#### Bandwidth Limits
- `TOR_BANDWIDTH_RATE` - Rate limit (e.g., "50 MBytes")
- `TOR_BANDWIDTH_BURST` - Burst limit (e.g., "100 MBytes")

#### Exit Policy (exit mode only)
- `TOR_EXIT_POLICY` - Custom exit policy (e.g., "accept *:80,accept *:443,reject *:*")

#### Official Tor Project Bridge Naming (Drop-in Compatibility)
- `NICKNAME` - Maps to TOR_NICKNAME
- `EMAIL` - Maps to TOR_CONTACT_INFO
- `OR_PORT` - Maps to TOR_ORPORT
- `PT_PORT` - Maps to TOR_OBFS4_PORT (auto-enables bridge mode)
- `OBFS4V_*` - Additional torrc options

### Docker Compose with ENV

```yaml
version: '3.8'

services:
  tor-relay:
    image: r3bo0tbx1/onion-relay:latest
    container_name: tor-relay
    restart: unless-stopped
    network_mode: host
    environment:
      TOR_RELAY_MODE: guard
      TOR_NICKNAME: MyRelay
      TOR_CONTACT_INFO: tor@example.com
      TOR_ORPORT: 9001
      TOR_BANDWIDTH_RATE: 50 MBytes
      TOR_BANDWIDTH_BURST: 100 MBytes
    volumes:
      - tor-data:/var/lib/tor

volumes:
  tor-data:
```

### Drop-in Replacement for Official Bridge

Fully compatible with `thetorproject/obfs4-bridge`:

```yaml
version: '3.8'

services:
  obfs4-bridge:
    image: r3bo0tbx1/onion-relay:latest
    container_name: obfs4-bridge
    restart: unless-stopped
    network_mode: host
    environment:
      # Official Tor Project ENV naming
      NICKNAME: MyBridge
      EMAIL: tor@example.com
      OR_PORT: 9001
      PT_PORT: 9002  # Auto-enables bridge mode
    volumes:
      - obfs4-data:/var/lib/tor

volumes:
  obfs4-data:
```

---

## Post-Deployment Verification

After deploying with any method, verify your relay is working:

### 1. Check Container Status

```bash
docker ps | grep tor-relay
```

Expected output:
```
CONTAINER ID   IMAGE                                    STATUS
abc123def456   r3bo0tbx1/onion-relay:latest    Up 5 minutes (healthy)
```

### 2. Run Diagnostics

The image provides **5 diagnostic tools**:

```bash
# Full health report with emojis
docker exec tor-relay status

# JSON health data (for automation)
docker exec tor-relay health

# Show fingerprint + Tor Metrics URL
docker exec tor-relay fingerprint

# Get bridge line (bridge mode only)
docker exec tor-relay bridge-line
```

**Expected output from `status`:**
- ✅ `Bootstrapped 100% (done): Done`
- ✅ `ORPort is reachable from the outside`
- ✅ No recent errors

### 3. Monitor Bootstrap Progress

```bash
# Stream logs to see bootstrap progress (0-100%)
docker logs -f tor-relay

# Check JSON health
docker exec tor-relay health
```

**Example JSON output:**
```json
{
  "status": "up",
  "pid": 1,
  "uptime": "01:00:00",
  "bootstrap": 100,
  "reachable": "true",
  "errors": 0,
  "fingerprint": "1234567890ABCDEF...",
  "nickname": "MyRelay"
}
```

### 4. Wait for Network Recognition

- **10-30 minutes**: Bootstrap completes (100%)
- **1-2 hours**: Relay appears on Tor Metrics
- **24-48 hours**: Full statistics available
- **8+ days**: Eligible for Guard flag (guard relays only)

Search for your relay:
- **Clearnet**: https://metrics.torproject.org/rs.html
- **Tor Browser**: http://hctxrvjzfpvmzh2jllqhgvvkoepxb4kfzdjm6h7egcwlumggtktiftid.onion/rs.html

---

## Firewall Configuration

### Required Ports

| Relay Type | Ports to Open |
|------------|---------------|
| **Guard/Middle** | 9001/tcp (ORPort) |
| **Exit** | 9001/tcp (ORPort) |
| **Bridge** | 9001/tcp (ORPort), 9002/tcp (obfs4) |

> **Note:** All ports are configurable via ENV variables or config file.

### UFW (Ubuntu/Debian)

```bash
# Guard/Exit relay
sudo ufw allow 9001/tcp  # ORPort

# Bridge relay
sudo ufw allow 9001/tcp  # ORPort
sudo ufw allow 9002/tcp  # obfs4 port

# Reload firewall
sudo ufw reload

# Verify rules
sudo ufw status
```

### firewalld (RHEL/CentOS)

```bash
# Guard/Exit relay
sudo firewall-cmd --permanent --add-port=9001/tcp

# Bridge relay
sudo firewall-cmd --permanent --add-port=9001/tcp
sudo firewall-cmd --permanent --add-port=9002/tcp

# Reload
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-all
```

### iptables (Advanced)

```bash
# Guard/Exit relay
sudo iptables -A INPUT -p tcp --dport 9001 -j ACCEPT

# Bridge relay
sudo iptables -A INPUT -p tcp --dport 9001 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9002 -j ACCEPT

# Save rules
sudo iptables-save > /etc/iptables/rules.v4
```

### Cloud Provider Firewalls
Don't forget to open ports in your cloud provider's firewall:
- **AWS**: Security Groups
- **Google Cloud**: Firewall Rules
- **Azure**: Network Security Groups
- **DigitalOcean**: Cloud Firewalls
- **Hetzner**: Firewall section
- **Linode**: Cloud Firewalls
- **Vultr**: Firewall Management
- **Netcup**: Firewall Rules

---

## Hosting Provider Recommendations

### 🏆 BEST for Exit Nodes

| Provider | Exit | Guard/Middle | Bridges | Starting Price | Locations | Notes |
|----------|------|--------------|---------|----------------|-----------|-------|
| **BuyVM** | ✅ | ✅ | ✅ | $2/mo | US, LU | Best value, unmetered bandwidth, often sold out |
| **MAXKO Hosting** | ✅ | ✅ | ✅ | ~$10/mo | HR, HU, BG, ZA | Code: TOR10, crypto accepted, underrepresented regions |
| **Privex** | ✅ (SE only) | ✅ | ✅ | €15/mo | SE, DE, FI, US, AU | Purpose-built for privacy, runs own relays, crypto required |
| **IncogNET** | ✅ | ✅ | ✅ | ~$10/mo | NL, US | Clear exit policy, requires port 80 notice page |
| **Linode** | ✅ (reduced) | ✅ | ✅ | $5/mo | 12+ locations | $100 free credits, reduced exit policy required |
| **1337 Services (RDP.sh)** | ✅ | ✅ | ✅ | ~€5/mo | DE | ⚠️ Overrepresented (4.33%) - avoid for diversity |

### ✅ Good for Exit Nodes (with caveats)

| Provider | Exit | Guard/Middle | Bridges | Starting Price | Locations | Caveat |
|----------|------|--------------|---------|----------------|-----------|--------|
| **Hetzner** | ✅ | ✅ | ✅ | €4.15/mo | DE, FI, US | ⚠️ Overrepresented (8.26%), good bandwidth |
| **Netcup** | ✅ | ✅ | ✅ | €2.50/mo | DE, AT, NL, US | ⚠️ Aggressive abuse handling (4.56%), best for relays |
| **LiteServer** | ✅ | ✅ | ✅ | ~€5/mo | NL | Reduced policy + notify support, 3.1% consensus weight |
| **Trabia** | ✅ | ✅ | ✅ | ~$5/mo | MD | Good for network diversity |
| **i3D** | ✅ | ✅ | ✅ | €10-30/mo | NL | If abuse handled properly, 0.02% consensus |
| **KoDDoS** | ✅ | ✅ | ✅ | ~$10/mo | NL | DDoS protection, Bitcoin accepted, 0.0% consensus |
| **PulseServers** | ✅ | ✅ | ✅ | ~$5/mo | US, FR, CA | ⚠️ Uses OVH network (11.14% overrepresented) |

### ✅ Excellent for Guard/Middle Relays (No Exits)

| Provider | Exit | Guard/Middle | Bridges | Starting Price | Locations | Notes |
|----------|------|--------------|---------|----------------|-----------|-------|
| **myLoc** | ❌ | ✅ | ✅ | €5/mo | DE | Reliable, good support, 0.76% consensus |
| **Worldstream** | ❌ | ✅ | ✅ | €10/mo | NL | Solid uptime, 0.34% consensus |
| **Creanova** | ❌ | ✅ | ✅ | €5/mo | FI | Good for diversity, 0.07% consensus |
| **DreamHost** | ❓ | ✅ | ✅ | $5/mo | US | Unconfirmed for exits, 0.01% consensus |
| **MilesWeb** | ❌ | ✅ | ✅ | $3/mo | RO, US, UK | Budget-friendly, multiple locations |

### 🌟 Privacy-Focused Providers

| Provider | Exit | Guard/Middle | Bridges | Starting Price | Locations | Notes |
|----------|------|--------------|---------|----------------|-----------|-------|
| **1984Hosting** | ✅ | ✅ | ✅ | ~$10/mo | IS | Free speech hoster, Iceland, 0.08% consensus |
| **FlokiNET** | ✅ | ✅ | ✅ | ~$10/mo | IS, RO, NL, FI | Sponsors Tor exits, 0.67% consensus |
| **NiceVPS** | ✅ | ✅ | ✅ | ~$5/mo | CH, NL | Crypto accepted, has onion site |
| **Ukrainian Data Network** | ✅ | ✅ | ✅ | ~$5/mo | UA | Free speech, crypto, 20TB fair use |

### 💰 Budget Champions

| Provider | Exit | Guard/Middle | Bridges | Starting Price | Locations | Notes |
|----------|------|--------------|---------|----------------|-----------|-------|
| **BuyVM** | ✅ | ✅ | ✅ | $2/mo | US, LU | Best value overall if in stock |
| **Netcup** | ✅ | ✅ | ✅ | €2.50/mo | DE, AT, NL, US | 40-120TB bandwidth, aggressive abuse handling |
| **VPSslim** | ✅ | ✅ | ✅ | ~$3/mo | NL | 2TB/day fair use, 0.08% consensus |
| **iHostArt** | ✅ | ✅ | ✅ | ~$5/mo | RO | Good diversity, Romania underrepresented |
| **Linode** | ✅ | ✅ | ✅ | $5/mo | Global | $100 free = ~20 months free |

### ⚠️ Providers with Restrictions

| Provider | Status | Notes |
|----------|--------|-------|
| **OVH/OVHcloud** | ❌ Exits | Middle/bridges OK. **Overrepresented (11.14%)** - avoid for diversity |
| **DigitalOcean** | ❌ Exits | Middle/bridges OK. May suspend without warning, 0.41% consensus |
| **Vultr** | ❌ Exits | Middle/bridges OK as of Oct 2024. Check current AUP, 0.08% consensus |
| **AWS** | ❌ Exits | Expensive bandwidth, middle relays possible but costly |
| **Google Cloud** | ⚠️ | May flag relay traffic, not recommended |
| **Azure** | ❌ Exits | Expensive, middle relays uncertain, 0.0% consensus |

### ❌ AVOID - Banned or Problematic

| Provider | Reason |
|----------|--------|
| **Contabo** | Explicitly bans all Tor nodes in Section 2.9 of TOS |
| **HitMe.pl** | Blocks accounts on first abuse report |
| **Slask DataCenter** | No longer allows Tor traffic (Poland) |
| **ColoCrossing/HostPapa** | All Tor nodes banned |
| **GreenCloud** | Explicitly bans Tor in TOS |
| **Spectrum** | Residential ISP - TOS violation |
| **Astound Broadband** | Disallows servers/proxies |
| **Time4VPS** | Lithuania - explicitly prohibits Tor in TOS |

### 💡 Quick Selection Guide

**For Exit Nodes:**
- **Best Value**: BuyVM ($2/mo) if available
- **Best Support**: MAXKO Hosting (~$10/mo) - use code TOR10
- **Best Testing**: Linode ($5/mo + $100 credits)
- **Budget + High Maintenance OK**: Netcup (€2.50/mo)
- **Privacy-Focused**: Privex (€15/mo) or 1984Hosting (~$10/mo)

**For Guard/Middle Relays:**
- **Best Overall**: Netcup (€2.50/mo) or Hetzner (€4.15/mo)
- **Best Reliability**: myLoc (€5/mo)
- **Good Diversity**: Creanova (€5/mo) or MilesWeb ($3/mo)

**For Bridges:**
- **Best Privacy**: 1984Hosting (~$10/mo)
- **Best Value**: Netcup (€2.50/mo) or BuyVM ($2/mo)
- **Multiple Locations**: FlokiNET (~$10/mo)

**For Network Diversity (Underrepresented Regions):**
- MAXKO Hosting (Croatia, Hungary, Bulgaria, South Africa)
- Trabia (Moldova) - 0.09% consensus
- Ukrainian Data Network (Ukraine)
- iHostArt (Romania)
- i3D (Netherlands) - 0.02% consensus
- KoDDoS (Netherlands) - 0.0% consensus

### ⚠️ Network Diversity Warning

**Avoid these for NEW relays** (already overrepresented):
- OVH/OVHcloud: 11.14% ❌
- Hetzner: 8.26% ❌
- Netcup: 4.56% ⚠️
- 1337 Services/RDP.sh: 4.33% ⚠️
- LiteServer: 3.1% ⚠️
- BuyVM/Frantech: 2.22% ⚠️

**Ideal providers** (under 1% consensus weight):
- i3D: 0.02%
- KoDDoS: 0.0%
- Trabia: 0.09%
- MAXKO: 0.27%
- Creanova: 0.07%
- VPSslim: 0.08%

Choose providers with <1% consensus weight for better network health.

---

### 🏠 Home Hosting Considerations

**Pros:**
- Free bandwidth (usually)
- Full control over hardware
- Can run 24/7 on low-power devices (Raspberry Pi, old laptop)
- No monthly VPS costs

**Cons:**
- ISP may have ToS restrictions (check first!)
- Residential IP might be less trusted by Tor network
- Dynamic IP issues (use DynDNS or similar)
- Home network security risks (isolate on separate VLAN)
- Slower upload speeds on consumer connections
- Your home IP will be public in Tor directory
- Can attract unwanted attention to your home address

**ISP Considerations:**
- **Comcast**: Exits require commercial plan + prior contact; middle relays generally OK
- **Spectrum**: Prohibited by TOS
- **CenturyLink/Lumen**: Home TOS doesn't explicitly ban servers
- **Most cable ISPs**: Check TOS - many prohibit "servers"
- **TekSavvy** (Canada): Server-friendly, supports Tor
- **MonkeyBrains** (US): Allows Tor but colocation only

**Recommendation**: 
- ✅ **Bridges**: Safe for home networks (won't be publicly listed)
- ⚠️ **Guard/Middle relays**: Check ISP TOS first, use VPS if uncertain
- ❌ **Exit nodes**: Never on residential - use VPS with clear exit policy

**If running at home:**
1. Verify ISP TOS allows servers/relays
2. Use static IP or dynamic DNS (DuckDNS, No-IP)
3. Isolate relay on separate VLAN/network segment
4. Set bandwidth limits with AccountingMax (e.g., 80% of your upload speed)
5. Monitor for abuse complaints (shouldn't get any for bridges/middle)
6. Only run bridges or middle relays, never exits
7. Consider power consumption (Raspberry Pi uses ~5W)

**Best home setup**: Raspberry Pi 4 (4GB+ RAM) running Debian, dedicated to Tor bridge only.

---

## Monitoring Setup

### Option 1: JSON Health API

The `health` tool outputs JSON for monitoring integration:

```bash
# Get health status (raw JSON)
docker exec tor-relay health

# Parse with jq (requires jq on host)
docker exec tor-relay health | jq .

# Check specific field
docker exec tor-relay health | jq .bootstrap
```

### Option 2: Manual Monitoring Script

```bash
#!/bin/bash
# Save as: /usr/local/bin/check-tor-relay.sh

CONTAINER="tor-relay"

echo "🧅 Tor Relay Health Check - $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER"; then
    echo "❌ CRITICAL: Container not running!"
    exit 2
fi

# Run diagnostics
docker exec "$CONTAINER" status

# Check for errors in recent logs
ERRORS=$(docker logs "$CONTAINER" --tail 100 2>&1 | grep -iE "(error|critical)" | wc -l)

if [ "$ERRORS" -gt 5 ]; then
    echo "⚠️  WARNING: $ERRORS recent errors detected"
    exit 1
fi

echo "✅ Relay is healthy"
exit 0
```

Make it executable and add to cron:
```bash
chmod +x /usr/local/bin/check-tor-relay.sh

# Add to crontab (check every 6 hours)
crontab -e
0 */6 * * * /usr/local/bin/check-tor-relay.sh >> /var/log/tor-health.log 2>&1
```

### Option 3: Prometheus + Grafana

Use the `health` tool with Prometheus node_exporter textfile collector:

```bash
#!/bin/bash
# Save as: /usr/local/bin/tor-metrics-exporter.sh
# Requires: jq installed on host (apt install jq / brew install jq)

HEALTH=$(docker exec tor-relay health)

# Export metrics
echo "$HEALTH" | jq -r '
  "tor_bootstrap_percent \(.bootstrap)",
  "tor_reachable \(if .reachable == "true" then 1 else 0 end)"
' > /var/lib/node_exporter/textfile_collector/tor.prom
```

Run via cron every 5 minutes:
```bash
*/5 * * * * /usr/local/bin/tor-metrics-exporter.sh
```

> 📖 **Complete guide:** See [Monitoring Documentation](MONITORING.md) for advanced setups.

---

## Troubleshooting Deployments

### Container Won't Start

```bash
# Check Docker logs
docker logs tor-relay --tail 50

# Validate configuration (if using mounted config)
docker run --rm \
  -v ~/tor-relay/relay.conf:/etc/tor/torrc:ro \
  r3bo0tbx1/onion-relay:latest \
  tor --verify-config -f /etc/tor/torrc
```

### Ports Not Accessible

```bash
# Test from outside your network
nc -zv YOUR_PUBLIC_IP 9001

# Check local listening
sudo netstat -tulpn | grep 9001
```

### Configuration Not Loading

```bash
# Verify mount path
docker inspect tor-relay | grep -A 10 Mounts

# Check file permissions
ls -la ~/tor-relay/relay.conf

# View generated config (ENV mode)
docker exec tor-relay cat /etc/tor/torrc
```

### Bootstrap Stuck

```bash
# Check bootstrap progress
docker exec tor-relay health | jq .bootstrap

# Check for errors
docker logs tor-relay --tail 100 | grep -i error

# Verify ports are open
docker exec tor-relay status
```

---

## Next Steps

After successful deployment:

1. ✅ Monitor logs for 24 hours
2. ✅ Verify on Tor Metrics (https://metrics.torproject.org/rs.html)
3. ✅ Set up monitoring/alerts with `health` JSON API
4. ✅ Join [Tor Relay Operators mailing list](https://lists.torproject.org/cgi-bin/mailman/listinfo/tor-relays)
5. ✅ Consider running multiple relays for better network contribution

---

## Support

- 📖 [Main README](../README.md)
- 🔧 [Tools Documentation](TOOLS.md) - Complete guide to the 5 diagnostic tools
- 📊 [Monitoring Guide](MONITORING.md) - External monitoring integration
- 🐛 [Report Issues](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💬 [Tor Project Forum](https://forum.torproject.net/)
- 📧 [Relay Operators List](https://lists.torproject.org/cgi-bin/mailman/listinfo/tor-relays)

---

## 📚 Additional Resources

- **Tor Project Good/Bad ISPs List**: https://community.torproject.org/relay/community-resources/good-bad-isps/
- **Tor Metrics**: https://metrics.torproject.org/ (check AS/country distribution)
- **Reduced Exit Policy**: https://trac.torproject.org/projects/tor/wiki/doc/ReducedExitPolicy
- **Exit Guidelines**: https://community.torproject.org/relay/community-resources/tor-exit-guidelines/
- **Abuse Templates**: https://community.torproject.org/relay/community-resources/tor-abuse-templates/