#!/bin/bash
set -e

PSK="${PSK}"
ONPREM_CIDR="${ONPREM_CIDR}"
PRIVATE_LB_IP="${PRIVATE_LB_IP}"
OCI_BGP_PEER_IP="${OCI_BGP_PEER_IP}"
OCI_BGP_AS="${OCI_BGP_AS}"
OCI_IPSEC_PEER="${OCI_IPSEC_PEER}"
CPE_BGP_AS="${CPE_BGP_AS}"

# install packages
apt-get update
apt-get install -y libreswan frr

# configure ipsec (libreswan)
cat > /etc/ipsec.conf <<EOF
# basic ipsec.conf allowing the remote to connect with the shared PSK
version 2.0
config setup
  nat_traversal=yes
  protostack=netkey

conn %default
  keyexchange=ikev2
  ike=aes256-sha2_256;modp2048
  esp=aes256-sha2_256
  dpdaction=clear
  dpddelay=30s
  dpdtimeout=120s
  rekey=no

conn to-oci
  left=%defaultroute
  leftid=%any
  leftauth=psk
  # only accept/connect to the configured OCI IPSec peer
  right=${OCI_IPSEC_PEER}
  rightid=${OCI_IPSEC_PEER}
  rightauth=psk
  auto=add
EOF

# write PSK (restrict to OCI IPSec peer)
cat > /etc/ipsec.secrets <<EOF
$OCI_IPSEC_PEER : PSK "$PSK"
EOF

# Enable and start ipsec
systemctl enable ipsec
systemctl restart ipsec

# Configure FRR (bgpd) to advertise onprem CIDR. Neighbor setup is left to be completed
# once the oracle side public IP is known (the Terraform-created IPSec connection will expose it).
cat > /etc/frr/daemons <<'EOF'
bgpd=yes
ospfd=no
ospf6d=no
zebra=yes
EOF

cat > /etc/frr/frr.conf <<EOF
frr version 7.5
service integrated-vtysh-config

router bgp $CPE_BGP_AS
  bgp router-id `hostname -I | awk '{print $1}'`
  # configure neighbor only if OCI_BGP_PEER_IP is provided (Terraform may write it later)
  {{ if ne(OCI_BGP_PEER_IP, "") }}
  neighbor $OCI_BGP_PEER_IP remote-as $OCI_BGP_AS
  {{ else }}
  # placeholder neighbor; update with the Oracle peer IP once known
  neighbor 0.0.0.0 remote-as $OCI_BGP_AS
  {{ end }}
  ! advertise the on-prem network via a network statement
  network $ONPREM_CIDR
!
EOF

# enable and start frr
systemctl enable frr
systemctl restart frr

# wait for BGP adjacency and install routes/ACLs for learned prefixes
for i in {1..60}; do
  if vtysh -c "show ip bgp summary" 2>/dev/null | grep -q "Established"; then
    break
  fi
  sleep 5
done

# collect learned prefixes from BGP and install iptables and routes
LEARNED_PREFIXES=$(vtysh -c "show ip bgp" 2>/dev/null | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}" | sort -u)
for p in $LEARNED_PREFIXES; do
  # allow forwarding to learned prefix
  iptables -C FORWARD -d $p -j ACCEPT 2>/dev/null || iptables -I FORWARD -d $p -j ACCEPT
  # install return route via ipsec virtual interface (common name ipsec0) if present
  ip route replace $p dev ipsec0 2>/dev/null || true
done

# ensure PRIVATE_LB_IP is reachable via the tunnel
if [ -n "$PRIVATE_LB_IP" ]; then
  iptables -C FORWARD -d $PRIVATE_LB_IP/32 -j ACCEPT 2>/dev/null || iptables -I FORWARD -d $PRIVATE_LB_IP/32 -j ACCEPT
  ip route replace $PRIVATE_LB_IP/32 dev ipsec0 2>/dev/null || true
fi

# simple check loop for oracle peer IP file (optional):
# terraform can write the oracle peer IP into instance metadata or a tag,
# or you can push a neighbor config once known.

# Install a reconciliation script and systemd timer to persist routes/ACLs learned via BGP
cat > /usr/local/bin/libreswan-reconcile.sh <<'SH'
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
chmod +x /usr/local/bin/libreswan-reconcile.sh

cat > /etc/systemd/system/libreswan-reconcile.service <<'UNIT'
[Unit]
Description=Libreswan reconciliation service
After=network.target ipsec.service frr.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/libreswan-reconcile.sh
Unit
UNIT

cat > /etc/systemd/system/libreswan-reconcile.timer <<'UNIT'
[Unit]
Description=Run Libreswan reconciliation every 1 minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload || true
systemctl enable --now libreswan-reconcile.timer || true

exit 0
