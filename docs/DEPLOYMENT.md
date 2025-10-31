# 🚀 Deployment Guide - Tor Guard Relay v1.4

Complete deployment instructions for various hosting environments.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Method 1: Docker CLI](#method-1-docker-cli)
- [Method 2: Docker Compose](#method-2-docker-compose)
- [Method 3: Cosmos Cloud](#method-3-cosmos-cloud)
- [Method 4: Portainer](#method-4-portainer)
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
- ✅ **Open firewall ports** (9001/tcp at minimum)
- ✅ **Prepared configuration file** (`relay.conf`)

---

## Method 1: Docker CLI

Perfect for quick deployments and testing.

### Step 1: Prepare Your Configuration

Create `relay.conf` file:

```bash
# Create config directory
mkdir -p ~/tor-relay
cd ~/tor-relay

# Download example config
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/examples/relay.conf

# edit
nano relay.conf
```

**Minimum required edits:**
- `Nickname` - Your relay name
- `ContactInfo` - Your email
- `ORPort` - Usually 9001
- `RelayBandwidthRate` - Your bandwidth limit

### Step 2: Pull the Image

```bash
docker pull ghcr.io/r3bo0tbx1/onion-relay:latest
```

### Step 3: Run the Container

```bash
docker run -d \
  --name guard-relay \
  --network host \
  -v ~/tor-relay/relay.conf:/etc/tor/torrc:ro \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  --restart unless-stopped \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

### Step 4: Verify Deployment

```bash
# Check container is running
docker ps | grep guard-relay

# Check logs
docker logs -f guard-relay

# Run diagnostics
docker exec guard-relay relay-status
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
# Download docker-compose.yml
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/templates/docker-compose.yml

# Download example config
curl -o relay.conf https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/examples/relay.conf
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
docker-compose exec tor-guard-relay relay-status
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

> **About Cosmos Cloud**: Created by [azukaar](https://github.com/azukaar), Cosmos Cloud is a self-hosted platform for managing Docker containers with a beautiful UI, automatic HTTPS, integrated auth, and smart automation features. It's like Portainer meets Traefik meets simplicity.
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

Paste your relay configuration (see [example config](../examples/relay.conf)). 

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
   curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/templates/cosmos-compose.json
   ```
4. Upload or paste the JSON content
5. **Optional**: Edit timezone if needed (default: `Asia/Tokyo`)
   ```json
   "TZ=Asia/Tokyo"  // Change to your timezone
   "TZ=America/New_York"  // US East Coast
   "TZ=Europe/London"     // UK
   "TZ=UTC"              // Universal
   ```

### Step 3: Deploy

1. Review the configuration
2. Click **Create**
3. Wait for container to start
4. Navigate to **ServApps** → **TorGuardRelay**
5. Click **Logs** to monitor bootstrap progress

### Step 4: Verify Deployment

From Cosmos UI, click **Console** (or use SSH):

```bash
docker exec TorGuardRelay relay-status
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

You can also manually trigger updates from the Cosmos UI.

---

## Method 4: Portainer

Great for GUI-based management.

### Step 1: Access Portainer

Navigate to your Portainer instance (usually `https://your-server:9443`)

### Step 2: Create Stack

1. Click **Stacks** → **Add Stack**
2. Name it: `tor-guard-relay`
3. Choose **Web editor**

### Step 3: Paste Stack Definition

```yaml
version: '3.8'

services:
  tor-guard-relay:
    image: ghcr.io/r3bo0tbx1/onion-relay:latest
    container_name: guard-relay
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

1. Click **Volumes** → **Add Volume**
2. Name: `tor-config`
3. Use **File Upload** to upload your `relay.conf`

### Step 5: Deploy

1. Click **Deploy the stack**
2. Navigate to **Containers** → `guard-relay`
3. Click **Logs** to monitor
4. Click **Console** → Connect to run diagnostics

---

## Post-Deployment Verification

After deploying with any method, verify your relay is working:

### 1. Check Container Status

```bash
docker ps | grep guard-relay
```

Expected output:
```
CONTAINER ID   IMAGE                                    STATUS
abc123def456   ghcr.io/r3bo0tbx1/onion-relay:latest    Up 5 minutes (healthy)
```

### 2. Run Full Diagnostic

```bash
docker exec guard-relay relay-status
```

Look for:
- ✅ `Bootstrapped 100% (done): Done`
- ✅ `ORPort is reachable from the outside`
- ✅ No recent errors

### 3. Check Your Fingerprint

```bash
docker exec guard-relay fingerprint
```

### 4. Wait for Network Recognition

- **1-2 hours**: Relay appears on Tor Metrics
- **24-48 hours**: Full statistics available
- **8+ days**: Eligible for Guard flag

Search for your relay:
- **Clearnet**: https://metrics.torproject.org/rs.html
- **Tor Browser**: http://hctxrvjzfpvmzh2jllqhgvvkoepxb4kfzdjm6h7egcwlumggtktiftid.onion/rs.html

---

## Firewall Configuration

### UFW (Ubuntu/Debian)

```bash
# Allow ORPort (required)
sudo ufw allow 9001/tcp

# Allow DirPort (optional but recommended)
sudo ufw allow 9030/tcp

# Reload firewall
sudo ufw reload

# Verify rules
sudo ufw status
```

### firewalld (RHEL/CentOS)

```bash
# Allow ORPort
sudo firewall-cmd --permanent --add-port=9001/tcp

# Allow DirPort
sudo firewall-cmd --permanent --add-port=9030/tcp

# Reload
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-all
```

### iptables (Advanced)

```bash
# Allow ORPort
sudo iptables -A INPUT -p tcp --dport 9001 -j ACCEPT

# Allow DirPort
sudo iptables -A INPUT -p tcp --dport 9030 -j ACCEPT

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

---

## Hosting Provider Recommendations

### ✅ Tor-Friendly Providers

| Provider | Notes | Starting Price |
|----------|-------|----------------|
| **Hetzner** | Tor-friendly, excellent bandwidth | €4.15/mo |
| **OVH** | Good for high-bandwidth relays | €3.50/mo |
| **Linode** | Reliable, easy to use | $5/mo |
| **DigitalOcean** | Simple setup, good docs | $4/mo |
| **Vultr** | Many locations, fair pricing | $2.50/mo |

### ⚠️ Providers with Restrictions

- **AWS**: No explicit ban, but expensive bandwidth
- **Google Cloud**: May flag relay traffic
- **Azure**: Check ToS carefully

### 🏠 Home Hosting Considerations

**Pros:**
- Free bandwidth (usually)
- Full control

**Cons:**
- ISP may have ToS restrictions
- Residential IP might be less trusted
- Dynamic IP issues
- Home network security risks

**Recommendation**: Use VPS for guard relays, home for bridges only.

---

## Monitoring Setup

### Option 1: Manual Monitoring Script

```bash
#!/bin/bash
# Save as: /usr/local/bin/check-tor-relay.sh

CONTAINER="guard-relay"

echo "🧅 Tor Relay Health Check - $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER"; then
    echo "❌ CRITICAL: Container not running!"
    exit 2
fi

# Run diagnostics
docker exec "$CONTAINER" relay-status

# Check for errors
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

### Option 2: Prometheus + Grafana

Coming soon! Watch the repo for monitoring stack templates.

---

## Troubleshooting Deployments

### Container Won't Start

```bash
# Check Docker logs
docker logs guard-relay --tail 50

# Validate configuration
docker run --rm \
  -v ~/tor-relay/relay.conf:/etc/tor/torrc:ro \
  ghcr.io/r3bo0tbx1/onion-relay:latest \
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
docker inspect guard-relay | grep -A 10 Mounts

# Check file permissions
ls -la ~/tor-relay/relay.conf
```

---

## Next Steps

After successful deployment:

1. ✅ Monitor logs for 24 hours
2. ✅ Verify on Tor Metrics
3. ✅ Set up monitoring/alerts
4. ✅ Join [Tor Relay Operators mailing list](https://lists.torproject.org/cgi-bin/mailman/listinfo/tor-relays)
5. ✅ Consider running multiple relays

---

## Support

- 📖 [Main README](../README.md)
- 🐛 [Report Issues](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💬 [Tor Project Forum](https://forum.torproject.net/)
- 📧 [Relay Operators List](https://lists.torproject.org/cgi-bin/mailman/listinfo/tor-relays)