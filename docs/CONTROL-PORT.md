# Control Port Configuration & Advanced Monitoring

This guide covers secure configuration of the Tor Control Port for advanced monitoring tools like **Nyx** (command-line monitor) and **Prometheus exporters**.

> **⚠️ Security Note:** The Control Port provides administrative access to your relay. Always use authentication and follow the security guidelines below.

## Table of Contents

* [Authentication Setup](#authentication-setup)
* [Configuration Methods](#configuration-methods)
* [Connecting to Your Relay](#connecting-to-your-relay)
* [Monitoring with Nyx](#monitoring-with-nyx)
* [Troubleshooting](#troubleshooting)

---

## Authentication Setup

Tor requires a hashed password to access the Control Port. We recommend using the built-in helper tool to generate this securely.

### Option A: Use the Helper Tool (Recommended)

The container includes a built-in utility called `gen-auth` that generates a secure 32-character password and the required configuration hash in one step.

Run the tool inside your container:

```bash
docker exec tor-relay gen-auth
````

**Example Output:**

```bash
╔════════════════════════════════════════════════════════════╗
║  Tor Control Port Authentication Generator                 ║
╚════════════════════════════════════════════════════════════╝

✓ Generated secure 32-character password

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Save this password (use for Nyx authentication):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   4xK8mP2qR9vL3nT6wY5sD1gH7jF0bN8c...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
2. Add this line to your torrc:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   HashedControlPassword 16:A1B2C3D4E5F6...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📝 Next steps:
   1. Edit your relay.conf and add the HashedControlPassword line above
   2. Restart your container: docker restart tor-relay
   3. Connect with Nyx using the password shown above

💡 Tip: Save the password in a secure password manager!
```

**Next Steps:**

1.  **Copy the Password**: Store this in a password manager. You will need it to log in to Nyx.
2.  **Copy the Hash**: Add the `HashedControlPassword ...` line to your `relay.conf` (or `torrc`).

### Option B: Manual Generation

If you prefer to generate credentials manually on your host machine:

```bash
# 1. Generate a 32-byte secure password
PASS=$(openssl rand -base64 32)
echo "Password: $PASS"

# 2. Generate the hash inside the container
docker exec tor-relay tor --hash-password "$PASS"
```

-----

## Configuration Methods

Choose **one** method based on your use case.

### Method A: Unix Domain Socket (Recommended)

**Best for:** Running Nyx or monitoring tools on the same host.
**Security:** Uses file system permissions; impossible to expose to the internet.

Add to your `relay.conf`:

```ini
# Disable TCP Control Port
ControlPort 0

# Enable Unix Domain Socket
ControlSocket /var/lib/tor/control_socket
ControlSocketsGroupWritable 1

# Add your generated hash
HashedControlPassword 16:YOUR_FULL_HASH_STRING_HERE
```

**Volume Configuration:**
Ensure your data volume is mounted so the host can access the socket file. If you are using standard docker volume names:

  * **Docker Volume Path:** `/var/lib/docker/volumes/tor-guard-data/_data/control_socket`
  * **Bind Mount Path:** If you mapped a host folder (e.g., `-v ./data:/var/lib/tor`), the socket will be in `./data/control_socket`.

### Method B: TCP Localhost

**Best for:** External monitoring tools (e.g., Prometheus) that cannot read Unix sockets.
**Requirement:** Works best with `--network host` mode.

Add to your `relay.conf`:

```ini
# Bind strictly to localhost
ControlPort 127.0.0.1:9051

# Add your generated hash
HashedControlPassword 16:YOUR_FULL_HASH_STRING_HERE
```

> **⚠️ CRITICAL SECURITY WARNING**
> Never use `ControlPort 0.0.0.0:9051` or `ControlPort 9051` in host network mode.
> This exposes your control interface to the public internet, allowing anyone to attack your relay.
> **Always bind to 127.0.0.1.**

-----

## Connecting to Your Relay

After updating your configuration, restart the container to apply changes:

```bash
docker restart tor-relay
```

Verify the port or socket is active:

```bash
docker logs tor-relay | grep -i "Opened Control listener"
```

-----

## Monitoring with Nyx

[Nyx](https://nyx.torproject.org/) provides real-time bandwidth graphs, connection tracking, and log monitoring.

### 1. Installation

Install Nyx on your **host machine**:

```bash
sudo apt install nyx
```

### 2. Connect

**If using Unix Socket (Method A):**

```bash
# Locate your volume mount point (example for standard docker volume)
nyx -s /var/lib/docker/volumes/tor-guard-data/_data/control_socket
```

**If using TCP (Method B):**

```bash
nyx -i 127.0.0.1:9051
```

*When prompted, enter the **plaintext password** generated by `gen-auth`.*

-----

## Advanced Integration

### Prometheus Exporter

If using **Method B (TCP)**, you can scrape metrics using the Prometheus Tor Exporter:

```bash
docker run -d \
  --name tor-exporter \
  --network host \
  atx/prometheus-tor_exporter \
  --tor.control-address=127.0.0.1:9051 \
  --tor.control-password="YOUR_PASSWORD_HERE"
```

### Automated Health Checks

You can check relay status via script using `nc` (Netcat):

```bash
echo -e 'AUTHENTICATE "YOUR_PASSWORD"\r\nGETINFO status/circuit-established\r\nQUIT' | nc 127.0.0.1 9051
```

Expected output:
```bash
250 OK
250-status/circuit-established=1
250 OK
250 closing connection
```

-----

## Troubleshooting

### "Authentication failed"

1.  **Wrong String**: Ensure you are using the *plaintext* password in Nyx, not the *hash*.
2.  **Config Mismatch**: Check that `HashedControlPassword` in `relay.conf` matches the hash generated by the tool.
3.  **Restart**: Did you `docker restart tor-relay` after editing the config?

### "Connection refused" or "No such file"

  * **Unix Socket**: Check permissions. The socket must be readable by the user running Nyx.
    ```bash
    sudo ls -la /var/lib/docker/volumes/tor-guard-data/_data/control_socket
    ```
  * **TCP**: Ensure the container is running and port 9051 is bound locally.
    ```bash
    netstat -tuln | grep 9051
    ```

### "Socket Permission Denied"

The socket file is created by the `root` or `tor` user inside the container. You may need to run Nyx with `sudo` or adjust your user groups to read the Docker volume directory.