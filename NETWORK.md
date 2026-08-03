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
