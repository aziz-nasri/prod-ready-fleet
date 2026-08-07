## Network Diagram:

![Screen preview](./network_diagram.svg)

### Why:

this design follows simple rule: nothing should be reachable only if it strictly need to be. so if a server is compromised the "blast radius" is small. unlike a flat design where everything could be exposed.

The proxy (srv1) is the only thing that has to be reachable from the internet. it is the most attacked surface. Putting it in the DMZ zone means if its compromised the attacker has no direct route to the app logic and database.

srv2 and srv3 hold the actual logic and the actual data they're the assets worth protecting. they are not meant to face risks niether has any reason to face the internet directly.

## Roles

| Server | role |Zone|
| ----------- | ----------- | ----------- |
|srv1|	Reverse proxy / edge (nginx or Caddy, TLS termination)|	DMZ|
|srv2|Application server|	Internal|
|srv3|Database + acts as internal DNS resolver|	Internal / Restricted|

## Subnet layout

- **10.0.0.28/28:** Managment (SSH jump access to all 3 boxes)
- **10.0.10.0/24:** DMZ (serv1's public-facing NIC)
- **10.0.20.0/24:** Internal (srv1's internal, srv2, srv3)

**why:** with this design we can have clear firewall rules between the zones. It give a room for for growth (we can later split the /24 into smaller subnets). Avoids the common 192.168.x.x range that can clash with home networks and VPNs.

**IP scheme**

| server | zone |IP|
| ----------- | ----------- | ----------- |
|srv1| DMZ leg|10.0.10.10|
|srv1| Internal leg |10.0.20.10|
|srv2| Internal|10.0.20.21|
|srv3|Internal|10.0.20.20|
|admin host| Managment|10.0.0.28|

**clarification:**

- srv1 act as router, not just a proxy: srv2/srv3's default route points at srv1's internal IP: 10.0.20.10, IP forwording is enabled and a masquerade/NAT rule was added so traffic from the internal zone gets translated to srv1's NAT adapter address on its way out

- Since the NAT adapter is what VirtualBox actually uses to simulate "the internet" (what is used in this project.), inbound public traffic physically arrives on the NAT interface, not the DMZ leg.

- The DMZ leg currently has only srv1 on it, no other host exists in that segment. So right now it's a trust-boundary placeholder: it exists to represent "this is where DMZ-tier hosts would live".

## DNS

**Setup:**

Internal DNS resolution is provided by dnsmasq, running on srv3 (db.lab.internal, 10.0.20.20), serving only the internal zone (10.0.20.0/24).

Each host in the fleet resolves by name rather than hardcoded IP:

| Hostname | IP |
| ----------- | ----------- |
|proxy.lab.internal|10.0.20.10|
|app.lab.internal|10.0.20.21|
|db.lab.internal|10.0.20.20|

- Static host mappings are defined in dnsmasq.d/lab.conf and dnsmasq is bound explicitly to the internal interface (bind-interfaces), so it does not answer queries from the DMZ leg or the NAT-facing adapter.

- Upstream forwarding is disabled dnsmasq answers only for lab.internal and does not resolve external domains, since nothing on the internal zone should need to reach the public internet directly.

- Each internal host's /etc/netplan config points its nameservers entry at 10.0.20.20, so name resolution is automatic on boot rather than requiring manual /etc/hosts edits per server.

**Why dnsmasq:**

dnsmasq was chosen over a full DNS server (BIND9) or static /etc/hosts files for three reasons:

- Right-sized for the fleet
- Avoids the maintenance problem of static hosts files
- It's the same tool that would handle DHCP if the fleet grew

**Why it doesn't forward external queries:**

Disabling upstream forwarding is a deliberate security choice. hosts on the internal zone have no legitimate reason to resolve public domains, since they never initiate outbound connections to the internet by design (only srv1's DMZ leg faces the internet).


