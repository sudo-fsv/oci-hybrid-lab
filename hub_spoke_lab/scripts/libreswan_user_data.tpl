#!/bin/sh -x

# This script bootstraps the Libreswan instance that will act as the CPE 
# for the IPSec tunnels to OCI.

# input variables
PSK_1="${PSK_1}"
PSK_2="${PSK_2}"
ONPREM_CIDR="${ONPREM_CIDR}"
PRIVATE_LB_IP="${PRIVATE_LB_IP}"
OCI_BGP_PEER_IP_1="${OCI_BGP_PEER_IP_1}"
OCI_BGP_PEER_IP_2="${OCI_BGP_PEER_IP_2}"
OCI_BGP_AS="${OCI_BGP_AS}"
OCI_IPSEC_PEER_1="${OCI_IPSEC_PEER_1}"
OCI_IPSEC_PEER_2="${OCI_IPSEC_PEER_2}"
CPE_BGP_AS="${CPE_BGP_AS}"
LIBRESWAN_PRIVATE_IP="${LIBRESWAN_PRIVATE_IP}"
LIBRESWAN_RESERVED_PUBLIC_IP="${LIBRESWAN_RESERVED_PUBLIC_IP}"

# enable ip forwarding
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.accept_redirects=0
sudo sysctl -w net.ipv4.conf.all.send_redirects=0
sudo sysctl -w net.ipv4.conf.default.send_redirects=0
sudo sysctl -w net.ipv4.conf.$(ip -o -4 addr list | grep "$LIBRESWAN_PRIVATE_IP" | awk '{print $2}' | head -n1).send_redirects=0
sudo sysctl -w net.ipv4.conf.default.accept_redirects=0
sudo sysctl -w net.ipv4.conf.$(ip -o -4 addr list | grep "$LIBRESWAN_PRIVATE_IP" | awk '{print $2}' | head -n1).accept_redirects=0

# install packages
sudo apt-get update
sudo apt-get install -y libreswan frr

# configure ipsec (libreswan)
sudo tee /etc/ipsec.conf > /dev/null <<EOF
# basic ipsec.conf allowing the remote to connect with the shared PSK
version 2.0
config setup
  protostack=netkey

conn to-oci-1
  left=$LIBRESWAN_PRIVATE_IP
  leftid=$LIBRESWAN_RESERVED_PUBLIC_IP
  right=$OCI_IPSEC_PEER_1
  rightid=$OCI_IPSEC_PEER_1
  leftsubnet=0.0.0.0/0 
  rightsubnet=0.0.0.0/0
  authby=secret
  auto=start
  ikev2=insist
  ike=aes_cbc256-sha2_384;modp1536
  phase2alg=aes_gcm256;modp1536 
  encapsulation=yes
  ikelifetime=28800s
  salifetime=3600s
  vti-interface=vti1
  vti-routing=no

conn to-oci-2
  left=$LIBRESWAN_PRIVATE_IP
  leftid=$LIBRESWAN_RESERVED_PUBLIC_IP
  # only accept/connect to the configured OCI IPSec peer 2
  right=$OCI_IPSEC_PEER_2
  rightid=$OCI_IPSEC_PEER_2
  authby=secret
  auto=start
  ikev2=insist
  ike=aes_cbc256-sha2_384;modp1536
  phase2alg=aes_gcm256;modp1536 
  encapsulation=yes
  ikelifetime=28800s
  salifetime=3600s
  vti-interface=vti2
  vti-routing=no
EOF

# write PSKs (restrict to OCI IPSec peer)
sudo tee /etc/ipsec.secrets > /dev/null <<EOF
$LIBRESWAN_RESERVED_PUBLIC_IP $OCI_IPSEC_PEER_1 : PSK "$PSK_1"
$LIBRESWAN_RESERVED_PUBLIC_IP $OCI_IPSEC_PEER_2 : PSK "$PSK_2"
EOF

# Enable and start ipsec
sudo systemctl enable ipsec
sudo systemctl restart ipsec

# Configure FRR (bgpd)
sudo tee /etc/frr/daemons > /dev/null <<'EOF'
bgpd=yes
ospfd=no
ospf6d=no
zebra=yes
EOF

sudo tee /etc/frr/frr.conf > /dev/null <<EOF
frr version 7.5
service integrated-vtysh-config
!
ip route add $OCI_BGP_PEER_IP_1 nexthop dev vti1
ip route add $OCI_BGP_PEER_IP_2 nexthop dev vti2
!
router bgp $CPE_BGP_AS
  bgp router-id $LIBRESWAN_PRIVATE_IP
  neighbor $OCI_BGP_PEER_IP_1 remote-as $OCI_BGP_AS
  neighbor $OCI_BGP_PEER_IP_2 remote-as $OCI_BGP_AS
  address-family ipv4 unicast
    network $ONPREM_CIDR
    neighbor $OCI_BGP_PEER_IP_1 next-hop-self
    neighbor $OCI_BGP_PEER_IP_1 soft-reconfiguration inbound
    neighbor $OCI_BGP_PEER_IP_1 route-map ACCEPT-OCI in
    neighbor $OCI_BGP_PEER_IP_1 route-map ACCEPT-OCI out
    neighbor $OCI_BGP_PEER_IP_2 next-hop-self
    neighbor $OCI_BGP_PEER_IP_2 soft-reconfiguration inbound
    neighbor $OCI_BGP_PEER_IP_2 route-map ACCEPT-OCI in
    neighbor $OCI_BGP_PEER_IP_2 route-map ACCEPT-OCI out
  exit-address-family
!
  ip prefix-list ACCEPT-OCI seq 5 permit $ONPREM_CIDR
!
  route-map ACCEPT-OCI permit 10
    match ip address prefix-list ACCEPT-OCI
    set local-preference 200
    set med 50
    exit-route-map
!
EOF

# enable and start frr
sudo systemctl enable frr
sudo systemctl restart frr

# wait for BGP adjacency and install routes/ACLs for learned prefixes
for i in {1..60}; do
  if sudo vtysh -c "show ip bgp summary" 2>/dev/null | grep -q "Established"; then
    break
  fi
  sleep 5
done

# collect learned prefixes from BGP and install iptables and routes
LEARNED_PREFIXES=$(vtysh -c "show ip bgp" 2>/dev/null | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}" | sort -u)
for p in $LEARNED_PREFIXES; do
  # allow forwarding to learned prefix
  sudo iptables -C FORWARD -d $p -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -d $p -j ACCEPT
  # install return route via ipsec virtual interface (common name ipsec0) if present
  sudo ip route replace $p dev ipsec0 2>/dev/null || true
done

# ensure PRIVATE_LB_IP is reachable via the tunnel
if [ -n "$PRIVATE_LB_IP" ]; then
  sudo iptables -C FORWARD -d $PRIVATE_LB_IP/32 -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -d $PRIVATE_LB_IP/32 -j ACCEPT
  sudo ip route replace $PRIVATE_LB_IP/32 dev ipsec0 2>/dev/null || true
fi

# Install a reconciliation script and systemd timer to persist routes/ACLs learned via BGP
sudo tee /usr/local/bin/libreswan-reconcile.sh > /dev/null <<'SH'
#!/bin/bash
set -e
# wait a short time for FRR/ipsec to settle
sleep 5

# collect learned prefixes from BGP and install iptables and routes
LEARNED_PREFIXES=$(vtysh -c "show ip bgp" 2>/dev/null | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}" | sort -u)
for p in $LEARNED_PREFIXES; do
  iptables -C FORWARD -d $p -j ACCEPT 2>/dev/null || iptables -I FORWARD -d $p -j ACCEPT
  ip route replace $p dev ipsec0 2>/dev/null || true
done

# ensure PRIVATE_LB_IP route exists
if [ -n "$PRIVATE_LB_IP" ]; then
  iptables -C FORWARD -d $PRIVATE_LB_IP/32 -j ACCEPT 2>/dev/null || iptables -I FORWARD -d $PRIVATE_LB_IP/32 -j ACCEPT
  ip route replace $PRIVATE_LB_IP/32 dev ipsec0 2>/dev/null || true
fi

exit 0
SH
sudo chmod +x /usr/local/bin/libreswan-reconcile.sh

sudo tee /etc/systemd/system/libreswan-reconcile.service > /dev/null <<'UNIT'
[Unit]
Description=Libreswan reconciliation service
After=network.target ipsec.service frr.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/libreswan-reconcile.sh
UNIT

sudo tee /etc/systemd/system/libreswan-reconcile.timer > /dev/null <<'UNIT'
[Unit]
Description=Run Libreswan reconciliation every 1 minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

sudo systemctl daemon-reload || true
sudo systemctl enable --now libreswan-reconcile.timer || true

exit 0