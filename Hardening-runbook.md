## Section 1: System Update

**Applies to**: All servers

**Risk level**: Modetrate - a mistake here could lunch a system update in an unwanted time potentially slowing the server or forcing a reboot.

### 1.1 Install the unattended-upgrades
Install this package to automatically install security updates.

`sudo apt update`

`sudo apt install unattended-upgrades`

`sudo dpkg-reconfigure -plow unattended-upgrades`

### 1.2 Edit the configuration file.
You can edit configurations in /etc/apt/apt.conf.d/50unattended-upgrades. by default it only install security updates. you can configure it to remove unused dependencies, automatic reboot, Email notification and packages blacklist.

### 1.3 Update the system occasionally.
why: hakers could exploit installed softwares vunrabilites.
run this occasionally

`sudo apt upadate`

`sudo apt upgrade`

**Automated equivalent:** common/harden.sh (it runs a system update every week.)

## Section 2: Minimazing the attack surface.
**Applies to**: All servers

### 2.1 Remove unused packages.
why: hakers could exploit installed softwares vunrabilites.
run this to remove unused packages

`sudo apt autoremove --purge`

`sudo apt clean`

**Automatd equivament:** common/harden.sh

### 2.2 Disable/stop unnecessary services (daemons)
why: unecessary backgroud running services could be potentially exploited by hakers.

**setp 1:** 
Check all the services and all the running services. find any services you don't recognize or you don't need.

Currently running services

`systemctl list-units --type=service --state=running`

All installed services (enabled + disabled)

`systemctl list-unit-files --type=service`

**setp 2:**
Investigate the service.

`sudo systemctl status servicename` 

**step 3:**
Disable and stop the service.

`sudo systemctl stop service name`

`sudo systemctl disalbe --now servicename`

## Section 3: SSH Hardening

**Applies to:** All servers

**Risk level:** High a mistake here can lock you out of the server. Do not close your current SSH session until Step 3.4 is verified.

### 3.1 Confirm your SSH key is already installed
Before disabling password login, verify your public key is already present on the server.

`cat ~/.ssh/authorized_keys`

**Expected output:** one line starting with ssh-ed25519 or ssh-rsa, ending in your key comment (e.g. you@laptop).
**Red flag:** empty file or "No such file or directory". do not proceed until this is fixed.

### 3.2 Disable password authentication, root login and non-standard port.

**Why:** password auth is brute-forceable; direct root login removes your audit trail (you can't tell which admin logged in as root).

`sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)`

`sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config`

`sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config`

`sudo sed -i 's/^#\?Port 22.*/Port 2307/' /etc/ssh/sshd_config`

A backup of the original config is made automatically before editing, in case you need to revert.

### 3.3 Restart the SSH service

`sudo systemctl restart sshd`

Do not log out yet.

### 3.4 Verify in a NEW terminal window (keep your current session open)

`ssh -i ~/.ssh/id_ed25519 youruser@<server-ip>`

**Expected:** you connect successfully using your key, no password prompt.
**Red flag:** connection refused or password prompt still appears. do not close your original session. Go to Rollback below.

### 3.5 Confirm root login is blocked

`ssh root@<server-ip>`

**Expected:** Permission denied (publickey).
This confirms root login is disabled and only key-based, non-root access works.

**Rollback (if Step 3.4 fails)**

From your still-open original session:

`sudo cp /etc/ssh/sshd_config.bak.<timestamp> /etc/ssh/sshd_config`

`sudo systemctl restart sshd`

Then re-check Step 3.1 before retrying. a missing or malformed authorized_keys file is the most common cause of failure here.

### Automatd equivalent: common/harden.sh

## Section 4: Firewall

**Applies to:**  all servers 

**Risk level:** moderate - high, Attackers could more easily discover and exploit open services or vulnerabilities, potentially leading to unauthorized access, data breaches, or system compromise.

### 4.1 install the nftable package
nftables is the modern Linux packet filtering and classification framework.

`sudo apt install nftables`

and enable it

`sudo systemctl enable --now nftables`

### 4.2 Check if any rules are applied
run:

`nft list ruleset`

or check the " /etc/nftables.conf " file

You can clear any rules by running:

`nft flush ruleset`   (use it carefully.)

### 4.3 Add the default inboud deny rule

run:

`sudo nft add table inet filter`  (To create a table.)

`sudo nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }`  (add the rule.)

### 4.4 Allow loopback, established and related connections, SSH and IMCP.
**why:** necessary connections for the functionality of the server.

Run the following commands:

` sudo nft add rule inet filter input iif "lo" accept`  (Allow loopback)

`sudo nft add rule inet filter input ct state established,related accept`  (Allow established and related connections)

`sudo nft add rule inet filter input tcp dport [your ssh port] accept`  (Allow ssh)

`sudo nft add rule inet filter input ip protocol icmp accept`  (Allow IMCP)

`sudo nft add rule inet filter input ip6 nexthdr icmpv6 accept`  (Allow IMCPv6)

### 4.5 Load the ruleset so it became persistent
**why**: persistent when rebooting. the rules stay after rebooting the system.

`sudo nft -f /etc/nftables.conf`

or write the rules manually in " /etc/nftables.conf "

### Automated equivalent: common/harden.sh

## Section 5: File ownership/permission 

### 5.1 Difine the correct baseline

Define what the baseline for system ownership and permission. 

focus on those high impact areas:

| Location | expected ownership & mode |
| ----------- | ----------- |
| /etc/passwd, /etc/shadow, /etc/group, /etc/gshadow| root:root 644 / 000 / 644 / 000|
| /etc/ssh/| root:root, keys 600, config 644|
|/etc/sudoers + /etc/sudoers.d/|root:root 440|
|/boot, /lib, /usr, /bin, /sbin|root:root|
|/var/log/|root:root or root:adm / syslog|
|Cron files (/etc/cron*, /var/spool/cron)|root:root 600/700|
|Web roots, application configs|Application user + restricted group|
|TLS keys, secrets, .env files|root or service user, mode 600|
|/home/*|user:user 750 or 700|

### 5.2 audit current state

Find world-writable files (very dangerous)

`find / -xdev -type f -perm -0002 -ls 2>/dev/null`

Find world-writable directories

`find / -xdev -type d -perm -0002 -ls 2>/dev/null`

Find SUID/SGID binaries

`find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -ls 2>/dev/null`

Check ownership of critical files

`ls -l /etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config`

Check for files not owned by root in system directories

`find /bin /sbin /usr/bin /usr/sbin /lib /lib64 -xdev ! -user root -ls 2>/dev/null`

### 5.3 Remediate systematically
Fix the highest-risk items first (shadow, sudoers, SSH keys, world-writable files).

Restore package-default permissions where possible:

`sudo apt install --reinstall <package>`


## Section 6: Application Server Hardening (srv2)

**Applies to:** srv2 (app server) only
Risk level: Moderate misconfiguring the firewall step can cut off the proxy's access to the app; verify from srv1 before moving on.

### 6.1 Create a dedicated non-root service account

**Why:** if the app process is ever compromised, it should not have root privileges on the box.

`sudo useradd -r -s /usr/sbin/nologin -d /opt/app appuser`

`sudo mkdir -p /opt/app`

`sudo chown -R appuser:appuser /opt/app`

**Verify:**

`id appuser`

**Expected:** user exists, shell is /usr/sbin/nologin (cannot be used for interactive login).

### 6.2 Bind the app to the internal interface only

**Why:** the app must be unreachable except through the proxy. Binding to 0.0.0.0 exposes it on every interface, including any future public one.

Edit the app's config/env file so it listens on the internal NIC's IP (e.g. 10.0.20.21) or 127.0.0.1 if the proxy connects via a local tunnel, not 0.0.0.0.

**Verify:**

`sudo ss -tlnp | grep 8080`

**Expected:** listening address is 10.0.20.21:8080, not 0.0.0.0:8080.
Red flag: 0.0.0.0:8080 the app is reachable from anywhere on the internal network, not just the proxy.

### 6.3 Restrict the local firewall to the proxy's IP only

**Why:** even on the internal network, only srv1 has a reason to reach this port.

`sudo nft add rule inet filter input ip saddr 10.0.20.10 tcp dport 8080 accept`

`sudo nft add rule inet filter input tcp dport 8080 drop`


**Verify from srv1:**

`curl -m 3 http://10.0.20.21:8080/health`

**Expected:** successful response.

**Verify from srv3** (should fail it has no legitimate reason to reach the app port):

`curl -m 3 http://10.0.20.21:8080/health`

**Expected:** connection timeout or refused.

### 6.4 Secure the environment/config file

**Why:** this file holds config and possibly secrets (DB credentials, API keys) it should be unreadable by anyone but the app itself.

`sudo chown appuser:appuser /opt/app/.env`

`sudo chmod 600 /opt/app/.env`

**Verify:**

`ls -l /opt/app/.env`

**Expected:** -rw------- 1 appuser appuser.

### 6.5 Disable debug mode

**Why:** debug modes commonly expose stack traces, environment variables, or admin endpoints a serious information leak if the box is ever probed.

Check the app's config for a DEBUG or ENV flag and confirm it's set to false / production.

**Verify:** request a deliberately invalid endpoint and confirm no stack trace or internal path is returned in the response.

### 6.6 Configure the systemd unit with resource limits and auto-restart

```
# /etc/systemd/system/app.service
[Unit]
Description=Application server
After=network.target

[Service]
User=appuser
Group=appuser
WorkingDirectory=/opt/app
EnvironmentFile=/opt/app/.env
ExecStart=/opt/app/bin/start
Restart=on-failure
MemoryMax=512M
TasksMax=100

[Install]
WantedBy=multi-user.target
```
`sudo systemctl daemon-reload`

`sudo systemctl enable --now app.service`


**Verify:**

`systemctl status app.service`

**Expected:** active (running), running as appuser not root.

**Rollback**

If the firewall rule in 6.3 blocks the proxy incorrectly:

`sudo nft flush ruleset`

Then reapply your saved base ruleset from firewall/nftables-internal.conf and redo Step 6.3 with the correct IP.

### 6.7 Close unecessary listrning ports

**why:** unecessary open ports could be a velnrability exploited by attackers

see the listening ports:

`sudo ss -ltnp`

close the unecessary ports:

`sudo kill -15 <PID>` (graceful kill.)

`sudo kill -9 <PID>` (Forceful kill if kill -15 doesn't work.)

**verify**: 

`sudo ss -ltnp`

all the killed process and their ports should not be listed.

### Automated Equivalent: roles/app/install.sh


## Section 7: Proxy Server Hardening (srv1)


**Applies to:** srv1 (proxy / NAT gateway) only

**Risk level:** High this box is internet-facing and the only route between zones. A firewall mistake here can either expose the internal zone or cut off legitimate access. Keep your management SSH session open until Step 7.6 is verified.

### 7.1 Disable nginx default site and hide version info

**Why:** the default nginx welcome page confirms nginx is running and its version, which is free reconnaissance for an attacker.

```
sudo rm -f /etc/nginx/sites-enabled/default
sudo sed -i 's/^#\?server_tokens.*/server_tokens off;/' /etc/nginx/nginx.conf
```

**Verify:**
```
curl -sI http://localhost | grep -i server
```
**Expected:** `Server: nginx` with no version number.
**Red flag:** a version string like `nginx/1.24.0` still appears.

### 7.2 Configure explicit server_name with a catch-all

**Why:** an unmatched or spoofed `Host` header should be rejected outright, not silently served by whichever block nginx picks by default.

```
# /etc/nginx/sites-available/proxy.conf
server {
    listen 443 ssl;
    server_name proxy.lab.internal;
    # TLS cert directives, proxy_pass to srv2 go here
}

server {
    listen 443 ssl default_server;
    server_name _;
    return 444;
}
```

```
sudo ln -sf /etc/nginx/sites-available/proxy.conf /etc/nginx/sites-enabled/
sudo nginx -t
```

**Verify:**
```
curl -sk https://localhost -H "Host: something-unexpected.com"
```
**Expected:** connection closed with no response (444).

### 7.3 Enable rate limiting

**Why:** without a limit, the proxy has no defense against a basic flood of requests hitting the app server behind it.

```
# in http block
limit_req_zone $binary_remote_addr zone=basic:10m rate=10r/s;

# in the proxy server block
location / {
    limit_req zone=basic burst=20 nodelay;
    proxy_pass http://10.0.20.21:8080;
}
```

```
sudo nginx -t && sudo systemctl reload nginx
```

**Verify:**
```
for i in {1..30}; do curl -s -o /dev/null -w "%{http_code}\n" https://localhost; done
```
**Expected:** first ~20 requests return `200`, later ones return `503`.

### 7.4 Restrict inbound firewall rules by interface

**Why:** with three NICs, each interface needs its own explicit rule IP-only rules don't guarantee traffic arrived on the interface it claims to.

```
NAT_IF="enp0s3"
INT_IF="enp0s9"

sudo nft add rule inet filter input iifname "$NAT_IF" tcp dport { 80, 443 } accept
sudo nft add rule inet filter input iifname "$INT_IF" ip saddr 10.0.0.0/28 tcp dport 22 accept
sudo nft add rule inet filter input drop
```

**Verify from the internal zone, confirm SSH works:**
```
ssh -i ~/.ssh/id_ed25519 admin@10.0.20.10   # from the management subnet only
```
**Expected:** connects normally.

**Verify confirm SSH is blocked on the DMZ/NAT side:**
```
ssh -p <forwarded-port> admin@127.0.0.1     #simulating a public attempt
```
**Expected:** connection refused or times out.

### 7.5 Restrict outbound forwarding to 80/443 only

**Why:** the internal zone should only reach the internet for the narrow case (e.g. `apt update`), never as a general-purpose route out.

```
sudo nft add rule inet filter forward iifname "$INT_IF" oifname "$NAT_IF" ip saddr 10.0.20.0/24 tcp dport { 80, 443 } accept
sudo nft add rule inet filter forward drop
```

**Verify from srv2:**
```
curl -m 3 -sI https://example.com   # should succeed
nc -zv -w3 example.com 22           # should fail port not in the allow list
```

### 7.6 Persist the ruleset and confirm reboot survival

```
sudo nft list ruleset | sudo tee /etc/nftables.conf
sudo systemctl enable nftables
sudo reboot
```

After reboot, re-run the verification commands from X.4 and X.5 to confirm the rules survived.

### Rollback

If Step 7.4 or 7.5 locks out legitimate access (e.g. your own SSH session):
```
sudo nft flush ruleset
```
Reconnect via the VirtualBox console (not SSH) if network access itself is broken, restore `/etc/nftables.conf.bak.<timestamp>`, and reapply rules one at a time, verifying after each.

Here's the DB + DNS hardening section for srv3, matching the format of your other runbook sections.

### Automated Equivalent : `roles/porxy/install.sh`



## Section 8: Database & DNS Server Hardening (srv3)

**Applies to:** srv3 (database + internal DNS) only

**Risk level:** High this box holds the fleet's data and is the sole DNS resolver for the internal zone. A misconfigured `pg_hba.conf` can either lock out the app or expose the database; a DNS misstep can break name resolution for every other server.

### 8.1 Bind PostgreSQL to the internal interface only

**Why:** the database must never be reachable from any interface but the internal zone it has no legitimate reason to listen anywhere else.

```
sudo sed -i "s/^#\?listen_addresses.*/listen_addresses = '10.0.20.20'/" /etc/postgresql/*/main/postgresql.conf
sudo systemctl restart postgresql
```

**Verify:**
```
sudo ss -tlnp | grep 5432
```
**Expected:** listening address is `10.0.20.20:5432`, not `0.0.0.0:5432` or `*:5432`.

### 8.2 Restrict client authentication to the app server only

**Why:** `pg_hba.conf` is the actual access-control layer binding to the right interface alone doesn't stop other hosts on the same subnet from connecting.

```
sudo cp /etc/postgresql/*/main/pg_hba.conf /etc/postgresql/*/main/pg_hba.conf.bak.$(date +%s)
```

Add this line to `pg_hba.conf`, above any broader `host all all` entries:
```
host    appdb    appuser    10.0.20.21/32    scram-sha-256
```

Ensure the `postgres` superuser is restricted to local-only access:
```
local   all      postgres                    peer
```

```
sudo systemctl reload postgresql
```

**Verify from srv2 (should succeed):**
```
psql -h 10.0.20.20 -U appuser -d appdb -c '\conninfo'
```

**Verify from srv1 (should fail):**
```
psql -h 10.0.20.20 -U appuser -d appdb -c '\conninfo'
```
**Expected:** `FATAL: no pg_hba.conf entry for host "10.0.10.10"...`

### 8.3 Create a least-privilege database role

**Why:** the app should never connect as `postgres`. A compromised app credential should only be able to touch its own database, not the whole cluster.

```
CREATE ROLE appuser WITH LOGIN PASSWORD 'REPLACE_ME';
CREATE DATABASE appdb OWNER appuser;
REVOKE ALL ON DATABASE appdb FROM PUBLIC;
GRANT CONNECT ON DATABASE appdb TO appuser;
```

**Verify:**
```sql
\du appuser
```
**Expected:** `appuser` has `Login` but not `Superuser`, `Createrole`, or `Createdb`.

### 8.4 Set connection limits

**Why:** caps the blast radius of a runaway or misbehaving app process exhausting database connections.

```
sudo sed -i "s/^#\?max_connections.*/max_connections = 40/" /etc/postgresql/*/main/postgresql.conf
sudo systemctl restart postgresql
```

**Verify:**
```
SHOW max_connections;
```

### 8.5 Restrict the local firewall to the app server's IP

```
sudo nft add rule inet filter input ip saddr 10.0.20.21 tcp dport 5432 accept
sudo nft add rule inet filter input tcp dport 5432 drop
```

**Verify from srv2:** connection on 8.2 above still succeeds.
**Verify from srv1:** `nc -zv -w3 10.0.20.20 5432` should fail.

### 8.6 Bind dnsmasq to the internal interface only

**Why:** DNS should answer queries from the internal zone exclusively not the DMZ or NAT-facing side of the fleet.

```
sudo tee -a /etc/dnsmasq.conf <<'EOF'
interface=enp0s3
bind-interfaces
no-resolv
EOF
sudo systemctl restart dnsmasq
```

`no-resolv` disables forwarding to any upstream resolver internal hosts get answers only for `lab.internal` names, nothing external.

**Verify:**
```
dig @10.0.20.20 db.lab.internal +short
```
**Expected:** returns `10.0.20.20`.

**Verify forwarding is actually disabled:**
```
dig @10.0.20.20 example.com +short
```
**Expected:** empty response or `SERVFAIL` — confirms no external DNS leak.

### 8.7 Restrict DNS access by firewall as well as by binding

Why: defense in depth don't rely on `bind-interfaces` alone.

```
sudo nft add rule inet filter input ip saddr 10.0.20.0/24 udp dport 5432 accept
sudo nft add rule inet filter input ip saddr 10.0.20.0/24 tcp dport 5432 accept
sudo nft add rule inet filter input udp dport 5432 drop
sudo nft add rule inet filter input tcp dport 5432 drop
```

**Verify from srv1 (DMZ leg, should fail):**
```
dig @10.0.20.20 db.lab.internal +short
```
**Expected:** timeout no response.

### 8.8 Confirm automated backups are running

```
systemctl list-timers | grep backup
sudo systemctl start backup.service   # trigger manually once
ls -la /var/backups/postgres/
```
**Expected:** a fresh postgresql main folder (or optionaly compressed ) with today's timestamp.

### Rollback

If `pg_hba.conf` changes lock out the app (Step 8.2):
```
sudo cp /etc/postgresql/*/main/pg_hba.conf.bak.<timestamp> /etc/postgresql/*/main/pg_hba.conf
sudo systemctl reload postgresql
```

If dnsmasq changes break resolution fleet-wide (Step 8.6/8.7):
```
sudo systemctl stop dnsmasq
```
Temporarily fall back to `/etc/hosts` entries on each host while you fix the config, then restart dnsmasq and re-verify.

## Section : Future improvments

### Mandatory acess control
SELinux (enforcing)

### Cryptography
Appling strong algorithms only

Keeping certificates currrent

### Disk Encryption
Full-disk or volume encryption where feasible (especially for sensitive data)

### Brute-force Protection
Fail2ban (or equivalent) for SSH and other exposed services

### Configuration Managment tools

using tools like Ansible, Puppet, Chef to enforce permessions and ownership.





