# FortiGate IKEv2/EAP VPN on a MikroTik Router – strongSwan Container Solution

| | |
|---|---|
| **Document version** | 1.0 |
| **Date** | 2026-11-11 |
| **Scope** | Connecting a MikroTik router (RouterOS 7.25.1) to a remote FortiGate VPN gateway that is normally accessed with FortiClient |
| **Profile name used in this document** | `Fortigate-IPSec-VPN` (placeholder) |

> **Placeholders.** Real names, user names, passwords, pre-shared keys and IP addresses are intentionally omitted.
> Values written as `<LIKE_THIS>` must be replaced with environment-specific data.

| Placeholder | Meaning |
|---|---|
| `<GATEWAY_IP>` | Public address of the remote FortiGate VPN gateway |
| `<REMOTE_SUBNET>` | Remote network (CIDR) reachable through the VPN |
| `<REMOTE_HOST_1>` | A host in the remote network that is permitted by the gateway |
| `<LAN_SUBNET>` | Local network behind the MikroTik router |
| `<CONTAINER_NET>` / `<CONTAINER_IP>` | Network and address used by the container on RouterOS |
| `<ROUTER_CONTAINER_IP>` | Router-side address of the container network (container default gateway) |
| `<VPN_USER>` / `<VPN_PASSWORD>` | VPN account credentials (EAP) |
| `<PRE_SHARED_KEY>` | Pre-shared key of the gateway |
| `<VIRTUAL_IP>` | Address assigned to the client by the gateway (mode-config) |
| `<SERVICE_PORT>` | TCP port of a service on a remote host, used for testing |
| `<STORAGE>` | RouterOS storage (disk) used by the container |

---

## 1. Summary

The remote site provides VPN access through FortiClient using an IPsec profile (`Fortigate-IPSec-VPN`). The goal was to establish the same
connection **directly from a MikroTik router**, so that all devices in the local network can reach the remote hosts without
FortiClient and without any additional hardware.

* A **native RouterOS IPsec configuration is not possible** with this profile: the gateway authenticates with a pre-shared key and then
  requires the user to log in with EAP, and RouterOS does not support this combination as an IKEv2 client. The gateway also ignores IKEv1.
* A **strongSwan client in a RouterOS container** negotiates the tunnel correctly, but in its default (kernel) mode the RouterOS kernel
  does not carry traffic through IPsec keys installed from inside a container.
* The **working solution** is a strongSwan container running in **user-space IPsec mode** (`kernel-libipsec` over the `/dev/net/tun`
  device that RouterOS provides to containers). The router only needs a route to the remote hosts pointing to the container.

---

## 2. Fortinet profile analysis

### 2.1 Source of the data

The configuration was taken from a FortiClient configuration export (FortiClient 7.2.4, Windows) and confirmed with a packet capture
of a real FortiClient connection. In the export the pre-shared key and the user name are stored encrypted (`EncX …` values), so they
are not readable and must be obtained from the gateway administrator.

### 2.2 Profile parameters

| Area | Parameter | Value in the profile | Meaning |
|---|---|---|---|
| General | Type | Manual IPsec VPN | Custom IPsec tunnel, not an automatic profile |
| IKE (phase 1) | IKE version | **2** | The gateway accepts IKEv2 only (see 3.2) |
| | Gateway authentication | **Pre-shared key** | The gateway proves its identity with the PSK |
| | User authentication (XAuth) | Enabled, user name prompted at connect time | With IKEv2 this is **EAP** user authentication |
| | Mode | `aggressive` (shown in the export) | Applies to IKEv1 only, ignored with IKEv2 |
| | Encryption / integrity | AES-256 with SHA-256, AES-256 with SHA-512 | Two proposals offered |
| | DH group | **16** (MODP-4096) | |
| | IKE SA lifetime | 86400 s | |
| | NAT traversal | Enabled, keep-alive 5 s | UDP encapsulation (port 4500) |
| | Dead Peer Detection | Enabled, interval 5 s, 3 retries | |
| | IKE fragmentation | Disabled | |
| | Local ID / Peer ID | Empty | Default identities |
| | Mode-config (virtual IP) | Enabled | Address and DNS are assigned by the gateway |
| | Local LAN access | Enabled | Local network stays reachable while connected |
| IPsec (phase 2) | Encryption / integrity | AES-256 with SHA-256, AES-256 with SHA-512 | |
| | PFS / DH group | Enabled, group **16** | |
| | Child SA lifetime | 43200 s (and 5120 KB) | |
| | Replay detection | Enabled | |
| | Remote networks | `0.0.0.0/0` in the profile | In practice the gateway pushes a list of individual hosts (split tunnel); the client installs host routes for them |
| | IPv6 | Blocked in the client | |

### 2.3 Behaviour observed in the packet capture

| Observation | Detail |
|---|---|
| IKE_SA_INIT | The client offers two proposals (AES-256-CBC with SHA-256 or SHA-512, DH 16). The gateway selects **AES-256-CBC / HMAC-SHA2-256-128 / PRF-HMAC-SHA2-256 / MODP-4096** |
| Client capabilities | Only NAT-detection notifications are sent: no MOBIKE, no IKE fragmentation, no signature-hash negotiation |
| IKE_AUTH | **Five IKE_AUTH round trips**: identity, EAP challenge/response, EAP success, final authentication with configuration request and Child SA – the typical EAP-MSCHAPv2 sequence |
| NAT-T | After detection, all traffic uses UDP 4500 (IKE and ESP encapsulated) |
| Liveness | INFORMATIONAL (DPD) messages every 5 s |
| Result | The client receives a virtual IP and the permitted remote hosts |
| ICMP | Ping to the remote hosts does not work even from FortiClient – the gateway policy blocks it. Use TCP tests instead |

### 2.4 Resulting requirements for any replacement client

1. IKEv2 initiator with NAT-T (UDP 500 / 4500).
2. **Server authentication with a pre-shared key, client authentication with EAP-MSCHAPv2** (user name and password).
3. Mode-config: request an internal address (and DNS).
4. Proposals: AES-256-CBC, SHA-256 / SHA-512, DH/PFS group 16 (MODP-4096).
5. The client has to NAT or route its traffic to the remote network from the assigned virtual address.

---

## 3. Attempts to implement the connection on MikroTik

### 3.1 Attempt A – native RouterOS IPsec

Configuration used (RouterOS v7, version `7.25.1`):

```routeros
/ip ipsec profile
add name=fortigate-ipsec-vpn enc-algorithm=aes-256 hash-algorithm=sha256 dh-group=modp4096 \
    lifetime=1d nat-traversal=yes dpd-interval=5s dpd-maximum-failures=3
/ip ipsec proposal
add name=fortigate-ipsec-vpn enc-algorithms=aes-256-cbc auth-algorithms=sha256,sha512 \
    pfs-group=modp4096 lifetime=12h

/ip ipsec policy group add name=fortigate-ipsec-vpn
/ip ipsec policy
add group=fortigate-ipsec-vpn template=yes src-address=0.0.0.0/0 dst-address=<REMOTE_SUBNET> proposal=fortigate-ipsec-vpn

/ip firewall address-list add list=fortigate-ipsec-vpn-lan address=<LAN_SUBNET>
/ip ipsec mode-config add name=fortigate-ipsec-vpn responder=no src-address-list=fortigate-ipsec-vpn-lan

/ip ipsec peer
add name=fortigate-ipsec-vpn address=<GATEWAY_IP>/32 exchange-mode=ike2 profile=fortigate-ipsec-vpn
```

Three identity variants were evaluated:

| # | Identity configuration | Result | Cause |
|---|---|---|---|
| 1 | PSK with `exchange-mode=aggressive` (IKEv1, tested because other profiles use IKEv1 + XAuth) | Active Peers stays at **"message 1 sent"**; packet sniffer shows only outgoing packets | The gateway does **not answer IKEv1**. A capture of a FortiClient session compared with the router's packets showed IKEv2 (FortiClient) against IKEv1 aggressive mode (router) |
| 2 | `auth-method=eap`, `eap-methods=eap-mschapv2`, user name and password, `exchange-mode=ike2` | IKE_SA_INIT succeeds, then the log shows `AUTH not matching`, `peer failed to authorize`, `killing ike2 SA` | The gateway authenticates itself with the **pre-shared key**, whereas the RouterOS EAP client expects the gateway to authenticate with a **certificate**. RouterOS rejects the gateway's authentication payload |
| 3 | `auth-method=pre-shared-key` only | Not viable (not tested) | The gateway requires EAP user authentication, so a PSK-only client would be rejected |

### 3.2 Attempt B – strongSwan in a container, kernel IPsec mode

To obtain a client that supports "gateway PSK + user EAP", strongSwan (swanctl/charon) was run in a Debian container on RouterOS.
First tests used the default kernel IPsec backend.

* The tunnel was established completely: gateway authenticated by PSK, EAP-MSCHAPv2 succeeded, `IKE_SA ESTABLISHED`, `CHILD_SA INSTALLED`,
  virtual IP assigned.
* However the byte/packet counters stayed at **0**, and a TCP connection test from inside the container failed with `File exists`.
* `/proc/net/xfrm_stat` showed an increasing **`XfrmOutPolError`** counter; `ip xfrm state` displayed `encap (ERROR truncated)`.

**Conclusion:** strongSwan can install its policies and keys in the RouterOS kernel, but the RouterOS kernel does not use IPsec (xfrm)
state from within a container network namespace. This cannot be corrected from inside the container.

### 3.3 Why a native implementation is not possible in the current version

Two independent limitations prevent a single-device solution based on the router's own IPsec stack:

1. **Authentication method.** RouterOS cannot act as an IKEv2 client that verifies the gateway with a pre-shared key and then logs in
   with EAP. The RouterOS EAP client requires a certificate-based responder authentication. The gateway cannot be switched to IKEv1,
   because it ignores IKEv1.
2. **Kernel IPsec in containers.** The standard strongSwan backend (kernel IPsec) is not usable from RouterOS containers.

Native support would become possible if **either**:

* RouterOS adds an IKEv2 initiator mode "responder authenticated by PSK + initiator authenticated by EAP", **or**
* the gateway administrator provides a tunnel type RouterOS supports: IKEv2 with PSK only, IKEv1 with XAuth,
  or IKEv2/EAP with a gateway certificate.

Release notes of newer RouterOS versions should be checked periodically; the container solution below can then be retired.

### 3.4 Problems encountered while building the container solution

| Symptom | Cause | Fix |
|---|---|---|
| `required hardware device net/tun not available` when creating the container | `/dev/net/tun` was requested under `devices:`; that option is for physical devices. The node is already provided to containers by RouterOS | Remove the `devices:` entry |
| `start.sh: set: Illegal option -` | Windows (CRLF) line endings in uploaded scripts | Convert to LF, or strip `\r` when the container starts (done in the entrypoint) |
| Login stops after "server requested EAP_IDENTITY" | The `eap-mschapv2` plugin is not included in the minimal Debian packages | Install `libcharon-extauth-plugins` |
| `unable to create IPv4 routing table rule` | strongSwan tries to create policy routing (table 220), unsupported in the container | `install_routes = no`; the required route is added by the up/down script |
| Wrong NAT after reconnect | The gateway can assign a different virtual IP at each connection; old rules remained | Rules are removed at start and on tunnel-down, and re-created on tunnel-up |
| `plugin 'openssl' / 'agent' / 'gcm': failed to load` | Messages from the `swanctl` CLI tool, which tries a default plugin list | Harmless; suppressed by limiting the `swanctl` plugin list |

---

## 4. Proposed solution – strongSwan container in user-space IPsec mode

### 4.1 Concept

RouterOS lists `/dev/net/tun` among the device nodes available inside every container. strongSwan's **`kernel-libipsec`** plugin uses this
TUN device to perform IPsec (encryption, decryption, ESP encapsulation in UDP 4500) **entirely in user space**, so the RouterOS kernel
IPsec stack is not involved at all.

```
 Local LAN  ──►  MikroTik router  ──►  Container (Debian + strongSwan)  ══ IKEv2 / ESP-in-UDP ══►  FortiGate gateway  ──►  Remote hosts
 <LAN_SUBNET>     route to remote       charon + kernel-libipsec                  (NAT-T, UDP 500/4500)
                  hosts via the         TUN interface "ipsec0"
                  container             SNAT to <VIRTUAL_IP>
```

Traffic flow:

1. A local device sends a packet to a remote host; the router's route sends it to `<CONTAINER_IP>`.
2. In the container the packet is forwarded to the TUN interface `ipsec0`; iptables translates the source address to `<VIRTUAL_IP>`
   (the address granted by the gateway).
3. strongSwan reads the packet from `ipsec0`, encrypts it and sends it to the gateway over UDP (container → router → Internet, with NAT).
4. Replies follow the same path in reverse; connection tracking restores the original source/destination.

### 4.2 Requirements

* RouterOS v7 with the **`container`** package (ARM, ARM64 or x86); container mode enabled with `/system/device-mode/update container=yes`
  (requires physical confirmation on the device).
* Storage (internal or external disk) `<STORAGE>` for the container image and files.
* Internet access for the container at the first start (Debian image and strongSwan packages are downloaded).
* UDP 500 and 4500 allowed outbound from the container network to `<GATEWAY_IP>`.
* The router must masquerade (NAT) the container network to the Internet.

### 4.3 RouterOS configuration

```routeros
# --- Network for the container ---
/interface veth add name=veth-vpn address=<CONTAINER_IP>/<PREFIX> gateway=<ROUTER_CONTAINER_IP>
/interface bridge add name=br-vpn
/interface bridge port add bridge=br-vpn interface=veth-vpn
/ip address add address=<ROUTER_CONTAINER_IP>/<PREFIX> interface=br-vpn

# --- Internet access for the container (skip if an existing masquerade rule already covers <CONTAINER_NET>) ---
/ip firewall nat add chain=srcnat src-address=<CONTAINER_NET> out-interface-list=<WAN_LIST> \
    action=masquerade comment="VPN container to Internet"

# --- Routing: remote hosts are reached through the container ---
/ip route add dst-address=<REMOTE_HOST_1>/32 gateway=<CONTAINER_IP> comment="VPN via strongSwan container"
# (one route per permitted remote host, or <REMOTE_SUBNET> if the whole network is allowed)

# --- Container ---
/container mounts add name=vpn-files src=<STORAGE>/vpn dst=/opt/vpn
/container envs add name=vpn-env key=USERSPACE value=1

/container add remote-image=library/debian:bookworm-slim interface=veth-vpn \
    root-dir=<STORAGE>/containers/vpn mounts=vpn-files envlist=vpn-env \
    cmd="/bin/sh -c \"sed 's/\\r\$//' /opt/vpn/start.sh > /tmp/start.sh && exec /bin/sh /tmp/start.sh\"" \
    logging=yes start-on-boot=yes hostname=vpnclient comment="VPN strongSwan"

# when the status changes to "stopped" (image extracted):
/container start [find comment="VPN strongSwan"]
```

If the router's `forward` firewall chain is restrictive, allow traffic from `<LAN_SUBNET>` to the remote hosts through the container.

The same container can alternatively be created from a compose definition (RouterOS container/app import):

```yaml
services:
  vpnclient:
    image: debian:bookworm-slim
    container_name: vpn-strongswan
    hostname: vpnclient
    # strips Windows CR line endings from start.sh before running it
    command: ["/bin/sh", "-c", "sed 's/\\r$//' /opt/vpn/start.sh > /tmp/start.sh && exec /bin/sh /tmp/start.sh"]
    environment:
      USERSPACE: "1"        # user-space IPsec over /dev/net/tun
    volumes:
      - ./:/opt/vpn         # directory with the files described in section 4.4
    restart: unless-stopped
```

Do **not** add `devices: /dev/net/tun` or privilege options: the TUN node is already available to RouterOS containers.

### 4.4 Files mounted into the container (`/opt/vpn`)

| File | Purpose |
|---|---|
| `fortigate-ipsec-vpn.conf` | strongSwan (swanctl) connection definition and secrets |
| `fortigate-ipsec-vpn-updown.sh` | Script executed when the tunnel goes up/down (NAT, MSS, route to `ipsec0`) |
| `start.sh` | Container entrypoint: installs packages, writes configuration, starts the service |

#### 4.4.1 `fortigate-ipsec-vpn.conf` – service configuration

```
# strongSwan (swanctl) – mirrors the FortiClient "Fortigate-IPSec-VPN" profile
# IKEv2, gateway authentication = PSK, client authentication = EAP-MSCHAPv2, mode-config virtual IP
connections {
  fortigate-ipsec-vpn {
    version = 2
    remote_addrs = <GATEWAY_IP>
    vips = 0.0.0.0
    proposals = aes256-sha256-modp4096,aes256-sha512-modp4096
    rekey_time = 23h
    dpd_delay = 20s
    encap = yes
    mobike = no
    fragmentation = no
    send_certreq = no

    local {
      auth = eap-mschapv2
      id = "<VPN_USER>"
      eap_id = "<VPN_USER>"
    }
    remote {
      auth = psk
      id = %any
    }
    children {
      fortigate-ipsec-vpn {
        remote_ts = <REMOTE_SUBNET>
        esp_proposals = aes256-sha256-modp4096,aes256-sha512-modp4096
        rekey_time = 11h
        start_action = start
        dpd_action = restart
        close_action = start
        updown = /usr/local/sbin/fortigate-ipsec-vpn-updown.sh
      }
    }
  }
}

secrets {
  eap-fortigate-ipsec-vpn {
    id = "<VPN_USER>"
    secret = "<VPN_PASSWORD>"
  }
  ike-fortigate-ipsec-vpn {
    secret = "<PRE_SHARED_KEY>"
  }
}
```

| Parameter | Explanation |
|---|---|
| `version = 2` | IKEv2 – the only version the gateway answers |
| `remote_addrs` | Public address of the gateway |
| `vips = 0.0.0.0` | Request a virtual IP (and DNS) from the gateway – mode-config, as in the FortiClient profile |
| `proposals` / `esp_proposals` | AES-256-CBC with SHA-256 or SHA-512 and DH/PFS group 16 (`modp4096`) – identical to the profile; the gateway selects the SHA-256 variant |
| `rekey_time` (23 h / 11 h) | Slightly below the gateway lifetimes (24 h / 12 h) so the client always rekeys first |
| `dpd_delay`, `dpd_action = restart` | Dead-peer detection; the tunnel is restarted automatically when the gateway stops responding |
| `encap = yes` | UDP encapsulation of ESP (NAT-T). **Required**, because the user-space backend carries ESP only inside UDP 4500, and the container is behind NAT |
| `mobike = no`, `fragmentation = no`, `send_certreq = no` | Make the client behave like FortiClient (no MOBIKE, no IKE fragmentation, no certificate request) |
| `local.auth = eap-mschapv2` | Client authenticates with user name and password (EAP-MSCHAPv2) |
| `local.id`, `eap_id` | IKE identity and EAP identity = VPN user name |
| `remote.auth = psk`, `id = %any` | Gateway authenticates with the pre-shared key; any gateway identity is accepted |
| `remote_ts` | Remote traffic selector. It may be narrowed to the individual hosts the gateway permits (comma separated `/32` entries) |
| `start_action = start`, `close_action = start` | Establish the tunnel when the service starts and re-establish it whenever it is closed |
| `updown` | Script called on tunnel up/down |
| `secrets` | EAP password and gateway pre-shared key. **Sensitive**: the file is restricted to `root` (mode 600) inside the container |

#### 4.4.2 `fortigate-ipsec-vpn-updown.sh` – tunnel up/down actions

```sh
#!/bin/sh
# Called by strongSwan when the VPN child SA goes up/down.
# NATs everything going to the remote network to the virtual IP assigned by the FortiGate,
# clamps TCP MSS so that large packets fit through the tunnel,
# and routes the remote network into the user-space IPsec interface (ipsec0).
REMOTE="<REMOTE_SUBNET>"
VIP="${PLUTO_MY_SOURCEIP4_1:-$PLUTO_MY_SOURCEIP}"

IPT=iptables
$IPT -t nat -L >/dev/null 2>&1 || IPT=iptables-legacy

NAT="-d $REMOTE ! -s $VIP -j SNAT --to-source $VIP"
MSS="-d $REMOTE -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360"

case "$PLUTO_VERB" in
  up-client|up-host)
    $IPT -t nat    -I POSTROUTING $NAT
    $IPT -t mangle -I FORWARD     $MSS
    # user-space IPsec (kernel-libipsec): traffic must be routed into the TUN device ipsec0
    if ip link show ipsec0 >/dev/null 2>&1; then
      ip link set ipsec0 up 2>/dev/null
      ip addr add $VIP/32 dev ipsec0 2>/dev/null
      ip route replace $REMOTE dev ipsec0 src $VIP && echo "route $REMOTE -> ipsec0 (src $VIP)"
    fi
    echo "VPN up, virtual IP $VIP"
    ;;
  down-client|down-host)
    $IPT -t nat    -D POSTROUTING $NAT 2>/dev/null
    $IPT -t mangle -D FORWARD     $MSS 2>/dev/null
    ip route del $REMOTE dev ipsec0 2>/dev/null
    ip addr del $VIP/32 dev ipsec0 2>/dev/null
    echo "VPN down"
    ;;
esac
exit 0
```

| Action on tunnel-up | Reason |
|---|---|
| `SNAT … --to-source $VIP` | The gateway only accepts traffic from the virtual IP it assigned; local addresses are translated to it. The virtual IP can differ at every connection, so the rule is created dynamically |
| `TCPMSS --set-mss 1360` | Avoids fragmentation problems caused by encapsulation overhead |
| Assign `$VIP` to `ipsec0`, route `<REMOTE_SUBNET>` through `ipsec0` | Sends the traffic to strongSwan's user-space IPsec engine (required because `install_routes = no`) |

The reverse operations are executed on tunnel-down.

#### 4.4.3 `start.sh` – container entrypoint

```sh
#!/bin/sh
# Container entrypoint: installs strongSwan on first start (root-dir persists),
# then runs charon in the foreground and loads the connection from /opt/vpn.
#   USERSPACE=1 -> strongSwan user-space IPsec over TUN (used on RouterOS)
#   USERSPACE=0 -> kernel IPsec (standard Linux hosts only)
set -e

REMOTE_SUBNET="<REMOTE_SUBNET>"

PLUGDIR=/usr/lib/ipsec/plugins
if ! command -v swanctl >/dev/null 2>&1 || [ ! -e $PLUGDIR/libstrongswan-eap-mschapv2.so ]; then
  echo "Installing strongSwan..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    strongswan-charon strongswan-swanctl libcharon-extra-plugins \
    libstrongswan-extra-plugins libstrongswan-standard-plugins \
    iptables iproute2 ca-certificates
  # eap-mschapv2 lives in libcharon-extauth-plugins on Debian 12
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libcharon-extauth-plugins || true
fi
if [ -e $PLUGDIR/libstrongswan-eap-mschapv2.so ]; then
  echo "eap-mschapv2 plugin: OK"
else
  echo "ERROR: eap-mschapv2 plugin missing"; ls $PLUGDIR | grep -i eap || true
fi

mkdir -p /etc/swanctl/conf.d /usr/local/sbin
# strip Windows CR line endings while copying
sed 's/\r$//' /opt/vpn/fortigate-ipsec-vpn.conf      > /etc/swanctl/conf.d/fortigate-ipsec-vpn.conf
sed 's/\r$//' /opt/vpn/fortigate-ipsec-vpn-updown.sh > /usr/local/sbin/fortigate-ipsec-vpn-updown.sh
chmod 755 /usr/local/sbin/fortigate-ipsec-vpn-updown.sh
chmod 600 /etc/swanctl/conf.d/fortigate-ipsec-vpn.conf

echo 1 > /proc/sys/net/ipv4/ip_forward || echo "WARN: could not enable ip_forward"

if [ "${USERSPACE:-0}" = "1" ]; then LIBIPSEC=yes; else LIBIPSEC=no; fi
mkdir -p /etc/strongswan.d/charon
cat > /etc/strongswan.d/charon/kernel-libipsec.conf <<EOF
kernel-libipsec {
    load = $LIBIPSEC
}
EOF
# swanctl (the CLI tool) only needs a few plugins - avoids harmless "failed to load" warnings
cat > /etc/strongswan.d/swanctl-vpn.conf <<EOF
swanctl {
    load = random nonce pem pkcs1 pkcs8 x509 pubkey sha1 sha2 md5 aes gmp gcrypt
}
EOF
cat > /etc/strongswan.d/charon-logging-vpn.conf <<EOF
charon {
    # policy-routing table 220 can't be created in a RouterOS container;
    # the route is added by the up/down script instead
    install_routes = no
    filelog {
        stdout {
            path = /dev/stdout
            default = 1
            ike = 2
            cfg = 2
            net = 2
            enc = 2
            knl = 1
        }
    }
}
EOF

# remove NAT/MSS rules left over from a previous run (old virtual IP)
for T in nat mangle; do
  iptables -t $T -S 2>/dev/null | grep -- "-d $REMOTE_SUBNET" | grep -E "SNAT|TCPMSS" | \
    sed 's/^-A /-D /' | while read -r R; do eval iptables -t $T $R || true; done
done

if [ "${USERSPACE:-0}" = "1" ]; then
  # user-space IPsec needs a TUN device; RouterOS provides /dev/net/tun to containers
  mkdir -p /dev/net
  [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200 2>/dev/null || true
  if [ -c /dev/net/tun ]; then echo "TUN device: OK"; else echo "ERROR: /dev/net/tun not available"; fi
  ls $PLUGDIR | grep -q kernel-libipsec && echo "kernel-libipsec plugin: OK" || echo "ERROR: kernel-libipsec plugin missing"
fi

CHARON=/usr/lib/ipsec/charon
[ -x "$CHARON" ] || CHARON=/usr/libexec/ipsec/charon
$CHARON &
PID=$!

for i in 1 2 3 4 5 6 7 8 9 10; do
  swanctl --stats >/dev/null 2>&1 && break
  sleep 1
done
swanctl --load-all

wait $PID
```

| Step | Description |
|---|---|
| Package installation | On first start (when strongSwan or the `eap-mschapv2` plugin is missing) the packages are installed with `apt`. The container root directory is persistent, so this happens once. Includes `libcharon-extra-plugins` (contains `kernel-libipsec`) and `libcharon-extauth-plugins` (contains `eap-mschapv2`) |
| Configuration files | Connection file and up/down script are copied from the mounted directory (CR characters removed), with restricted permissions on the file holding the secrets |
| IP forwarding | Enabled so that the container can route traffic between the router and the tunnel |
| `kernel-libipsec` | Loaded only when `USERSPACE=1` |
| `install_routes = no` | The RouterOS kernel cannot create the policy routing rules strongSwan wants; the route is added by the up/down script |
| Logging | strongSwan logs to standard output, so it appears in the RouterOS container log |
| Clean-up | NAT/MSS rules left from a previous run (old virtual IP) are removed |
| Self-checks | Prints `TUN device: OK`, `kernel-libipsec plugin: OK`, `eap-mschapv2 plugin: OK` or an explicit error |
| Start | `charon` is started, then `swanctl --load-all` loads the connection; `start_action = start` brings the tunnel up |

### 4.5 Commissioning and verification

1. Place the three files (without Windows line endings if possible) in `<STORAGE>/vpn/` on the router.
2. Create the network, routes and container (section 4.3) and start the container.
3. Check the container log:
   ```routeros
   /log print where topics~"container"
   ```
   Expected messages: `eap-mschapv2 plugin: OK`, `TUN device: OK`, `kernel-libipsec plugin: OK`, then strongSwan messages similar to
   `authentication of '<GATEWAY_IP>' with pre-shared key successful`, `EAP method EAP_MSCHAPV2 succeeded`,
   `IKE_SA fortigate-ipsec-vpn[1] established`, `CHILD_SA fortigate-ipsec-vpn{1} established`, and finally the line `VPN up, virtual IP <VIRTUAL_IP>`.
4. Verify inside the container (`/container shell [find hostname=vpnclient]`):
   ```sh
   swanctl --list-sas                         # IKE SA ESTABLISHED, CHILD SA INSTALLED, virtual IP shown
   ip link show ipsec0                        # the user-space IPsec interface exists
   ip route show                              # route <REMOTE_SUBNET> dev ipsec0
   ip xfrm state                              # must be empty – confirms user-space mode
   iptables -t nat -S POSTROUTING             # SNAT rule to the current virtual IP
   nc -vz -w 5 <REMOTE_HOST_1> <SERVICE_PORT> # TCP test (package netcat-openbsd)
   ```
   The `in`/`out` packet counters in `swanctl --list-sas` must increase while testing.
5. From a device in `<LAN_SUBNET>` test a TCP connection to `<REMOTE_HOST_1>:<SERVICE_PORT>`.
   Do not use ping as the only test: the remote gateway policy blocks ICMP.

### 4.6 Troubleshooting

| Symptom | Probable cause / action |
|---|---|
| Container does not start, `/dev/net/tun` error in the log | The `devices:` option is set for the TUN device – remove it. Check that `container` mode is enabled in `device-mode` |
| `eap-mschapv2 plugin missing` | Package installation failed (no Internet for the container, DNS or NAT problem). Fix connectivity and restart |
| Log stops after `server requested EAP_IDENTITY` | The `eap-mschapv2` plugin is missing or the gateway does not answer – see log and the previous point |
| `AUTHENTICATION_FAILED` or EAP failure | Wrong user name, password or an account that is locked/expired; wrong pre-shared key shows as a failure at gateway authentication |
| `no proposal chosen` | Algorithms or DH group differ from the gateway – compare with section 2.2 |
| No reply to IKE_SA_INIT | UDP 500/4500 blocked or not NATed for the container network; verify with the packet sniffer on the router |
| Tunnel up but no traffic | `ip link show ipsec0` missing (kernel-libipsec not loaded – check `USERSPACE=1`), missing route on the router to the container, restrictive router `forward` firewall, or `swanctl --list-sas` counters at 0 |
| Connection works then drops periodically | The same account is used at the same time from another client (e.g. FortiClient); use a separate account for the router |
| Large transfers stall | MSS/MTU problem – lower the MSS value in the up/down script |

### 4.7 Operational notes and limitations

* **Credentials** are stored in clear text in `fortigate-ipsec-vpn.conf`. Restrict access to the router and its storage, and request a dedicated
  low-privilege VPN account for the router.
* **Virtual IP** can change at each reconnection; this is handled automatically by the up/down script.
* **One session per account**: avoid using the same account simultaneously in FortiClient and on the router.
* **Performance**: user-space IPsec is performed by the router CPU; it is adequate for administrative and application traffic, but
  throughput is lower than hardware/kernel IPsec.
* **Updates**: packages are installed on the first start and are not updated automatically. To update, recreate the container root
  directory (the configuration files remain in `<STORAGE>/vpn/`).
* **Container security**: RouterOS containers share the router's kernel and MikroTik states that no security guarantee is given for them.
  Run only trusted images and keep the router firewall strict.
* **Availability**: the tunnel depends on the router's container feature and on Internet access at first start. `start-on-boot=yes`
  and `start_action`/`dpd_action` provide automatic recovery after reboot or connection loss.
* **Future**: when RouterOS supports the required IKEv2 authentication (PSK for the gateway + EAP for the client), the native IPsec
  configuration from section 3.1 (identity `auth-method=eap` variant) should be re-tested and the container removed.

---

## Appendix A – parameter mapping

| FortiClient profile | strongSwan (`fortigate-ipsec-vpn.conf`) | Native RouterOS equivalent | Native RouterOS works? |
|---|---|---|---|
| IKE version 2 | `version = 2` | `exchange-mode=ike2` | Yes |
| Gateway authentication: pre-shared key | `remote { auth = psk }` + `ike-` secret | `auth-method=pre-shared-key` | Yes, alone |
| User authentication (XAuth → EAP) | `local { auth = eap-mschapv2 }` + `eap-` secret | `auth-method=eap` (expects a gateway certificate) | **No** – combination with the PSK gateway is unsupported |
| AES-256 / SHA-256, SHA-512 | `proposals`, `esp_proposals` | Profile and proposal objects | Yes |
| DH group 16 / PFS 16 | `modp4096` | `dh-group=modp4096`, `pfs-group=modp4096` | Yes |
| Lifetimes 86400 s / 43200 s | `rekey_time` 23 h / 11 h | `lifetime=1d`, `lifetime=12h` | Yes |
| NAT-T, keep-alive | `encap = yes` | `nat-traversal=yes` | Yes |
| DPD 5 s × 3 | `dpd_delay`, `dpd_action` | `dpd-interval`, `dpd-maximum-failures` | Yes |
| Mode-config virtual IP | `vips = 0.0.0.0` | `/ip ipsec mode-config` (`responder=no`) | Yes |
| IKE fragmentation off, no MOBIKE | `fragmentation = no`, `mobike = no` | – | – |
| Split tunnel (hosts pushed by the gateway) | `remote_ts`, route on the router | Policy template, routes | Yes |
