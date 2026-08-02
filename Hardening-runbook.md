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

### 2.2 Disable password authentication, root login and non-standard port.

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

**Automatd equivament:** common/harden.sh

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

**Automated equivalent:** common/harden.sh

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


## Section 6: Future improvments

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





