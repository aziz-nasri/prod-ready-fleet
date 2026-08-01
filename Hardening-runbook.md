## Section 1: System Upadte

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

**Automated equivalent:** common/system_update.sh (it runs a system update every week.)

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
**Risk level:** High a mistake here can lock you out of the server. Do not close your current SSH session until Step 2.4 is verified.

### 2.1 Confirm your SSH key is already installed
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

### 2.3 Restart the SSH service

`sudo systemctl restart sshd`

Do not log out yet.

### 2.4 Verify in a NEW terminal window (keep your current session open)

`ssh -i ~/.ssh/id_ed25519 youruser@<server-ip>`

**Expected:** you connect successfully using your key, no password prompt.
**Red flag:** connection refused or password prompt still appears. do not close your original session. Go to Rollback below.

### 2.5 Confirm root login is blocked

`ssh root@<server-ip>`

**Expected:** Permission denied (publickey).
This confirms root login is disabled and only key-based, non-root access works.

**Rollback (if Step 2.4 fails)**

From your still-open original session:

`sudo cp /etc/ssh/sshd_config.bak.<timestamp> /etc/ssh/sshd_config`

`sudo systemctl restart sshd`

Then re-check Step 2.1 before retrying. a missing or malformed authorized_keys file is the most common cause of failure here.

**Automatd equivament:** common/harden.sh







