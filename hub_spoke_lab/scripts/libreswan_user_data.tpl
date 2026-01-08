#!/bin/sh -x

# This script bootstraps the Libreswan instance that will act as the CPE 
# for the IPSec tunnels to OCI.

# input variables
PSK_1="${PSK_1}"
PSK_2="${PSK_2}"
ONPREM_CIDR="${ONPREM_CIDR}"
OCI_BGP_PEER_IP_1="${OCI_BGP_PEER_IP_1}"
OCI_BGP_PEER_IP_2="${OCI_BGP_PEER_IP_2}"
OCI_BGP_AS="${OCI_BGP_AS}"
OCI_IPSEC_PEER_1="${OCI_IPSEC_PEER_1}"
OCI_IPSEC_PEER_2="${OCI_IPSEC_PEER_2}"
CPE_BGP_AS="${CPE_BGP_AS}"
CPE_BGP_PEER_IP_1="${CPE_BGP_PEER_IP_1}"
CPE_BGP_PEER_IP_2="${CPE_BGP_PEER_IP_2}"
LIBRESWAN_PRIVATE_IP="${LIBRESWAN_PRIVATE_IP}"
LIBRESWAN_RESERVED_PUBLIC_IP="${LIBRESWAN_RESERVED_PUBLIC_IP}"

# configure resolv.conf to use Quad9 as primary DNS (Ubuntu)
# If /etc/resolv.conf is a symlink (commonly to systemd-resolved), back it up and replace it
if [ -L /etc/resolv.conf ] || [ -f /etc/resolv.conf ]; then
  sudo cp -a /etc/resolv.conf /etc/resolv.conf.backup || true
  sudo rm -f /etc/resolv.conf || true
fi
sudo tee /etc/resolv.conf > /dev/null <<'EOF'
nameserver 9.9.9.9
nameserver 127.0.0.53
options edns0 trust-ad
search .
EOF

# enable ip forwarding
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.accept_redirects=0
sudo sysctl -w net.ipv4.conf.all.send_redirects=0
sudo sysctl -w net.ipv4.conf.default.send_redirects=0
sudo sysctl -w net.ipv4.conf.$(ip -o -4 addr list | grep "$LIBRESWAN_PRIVATE_IP" | awk '{print $2}' | head -n1).send_redirects=0
sudo sysctl -w net.ipv4.conf.default.accept_redirects=0
sudo sysctl -w net.ipv4.conf.$(ip -o -4 addr list | grep "$LIBRESWAN_PRIVATE_IP" | awk '{print $2}' | head -n1).accept_redirects=0

# function to install a package with retry logic and avoid apt locking issues
apt_update_with_retry() {
  local attempts=10
  local count=0

  while [ $count -lt $attempts ]; do
    if sudo apt-get update; then
      return 0
    fi
    count=$((count + 1))
    sleep 10
  done
  return 1
}

install_with_retry() {
  local package=$1
  local attempts=10
  local count=0

  while [ $count -lt $attempts ]; do
    if sudo apt-get install -y "$package"; then
      return 0
    fi
    count=$((count + 1))
    sleep 10
  done
  return 1
}

# install packages with retry
apt_update_with_retry
install_with_retry libreswan
install_with_retry frr
install_with_retry firewalld

# add permanent rules to allow UDP/500 and UDP/4500 (IKE/NAT-T), TCP/22 (SSH), and ICMP from anywhere
sudo systemctl enable firewalld
sudo firewall-cmd --add-service="ssh"
sudo firewall-cmd --add-service="ipsec"
sudo firewall-cmd --add-service="bgp"
sudo firewall-cmd --add-rich-rule="rule family='ipv4' protocol value='icmp' accept"
sudo firewall-cmd --runtime-to-permanent
sudo systemctl restart firewalld
sudo firewall-cmd --list-all

# configure ipsec (libreswan)
sudo tee /etc/ipsec.conf > /dev/null <<EOF
version 2.0
config setup
  protostack=netkey

conn %default
  type=tunnel
  authby=secret
  auto=start
  ikev2=insist
  ike=aes_cbc256-sha2_384;modp1536
  phase2alg=aes_gcm256;modp1536 
  encapsulation=yes
  rekey=yes
  ikelifetime=28800s
  salifetime=3600s
  vti-routing=no
  leftsubnet=0.0.0.0/0 
  rightsubnet=0.0.0.0/0
  pfs=yes
  dpdaction=restart
  dpddelay=10
  dpdtimeout=30

conn to-oci-1
  left=$LIBRESWAN_PRIVATE_IP
  leftid=$LIBRESWAN_RESERVED_PUBLIC_IP
  right=$OCI_IPSEC_PEER_1
  rightid=$OCI_IPSEC_PEER_1
  mark=5/0xffffffff
  vti-interface=vti1
  leftvti=$CPE_BGP_PEER_IP_1

conn to-oci-2
  left=$LIBRESWAN_PRIVATE_IP
  leftid=$LIBRESWAN_RESERVED_PUBLIC_IP
  right=$OCI_IPSEC_PEER_2
  rightid=$OCI_IPSEC_PEER_2
  mark=6/0xffffffff
  vti-interface=vti2
  leftvti=$CPE_BGP_PEER_IP_2
EOF

# write PSKs (restrict to OCI IPSec peer)
sudo tee /etc/ipsec.secrets > /dev/null <<EOF
$LIBRESWAN_RESERVED_PUBLIC_IP $OCI_IPSEC_PEER_1 : PSK "$PSK_1"
$LIBRESWAN_RESERVED_PUBLIC_IP $OCI_IPSEC_PEER_2 : PSK "$PSK_2"
EOF

# start ipsec
sudo ipsec verify
sudo systemctl status ipsec
sudo systemctl start ipsec

# configure FRR (bgpd)
sudo tee /etc/frr/daemons > /dev/null <<'EOF'
bgpd=yes
ospfd=no
ospf6d=no
zebra=yes
EOF

sudo tee /etc/frr/frr.conf > /dev/null <<EOF
frr version 7.5
frr defaults traditional
service integrated-vtysh-config
!
hostname libreswan-cpe
log file /var/log/bgpd.log 
log stdout informational
!
router bgp $CPE_BGP_AS
  bgp router-id $LIBRESWAN_PRIVATE_IP
  timers 10 30
  neighbor $OCI_BGP_PEER_IP_1 remote-as $OCI_BGP_AS
  neighbor $OCI_BGP_PEER_IP_1 ebgp-multihop 10
  neighbor $OCI_BGP_PEER_IP_2 remote-as $OCI_BGP_AS
  neighbor $OCI_BGP_PEER_IP_2 ebgp-multihop 10

  address-family ipv4 unicast
    network $ONPREM_CIDR
    neighbor $OCI_BGP_PEER_IP_1 next-hop-self
    neighbor $OCI_BGP_PEER_IP_1 soft-reconfiguration inbound
    neighbor $OCI_BGP_PEER_IP_1 route-map ALLOW-IN in
    neighbor $OCI_BGP_PEER_IP_1 route-map ALLOW-OUT out
    neighbor $OCI_BGP_PEER_IP_2 next-hop-self
    neighbor $OCI_BGP_PEER_IP_2 soft-reconfiguration inbound
    neighbor $OCI_BGP_PEER_IP_2 route-map ALLOW-IN in
    neighbor $OCI_BGP_PEER_IP_2 route-map ALLOW-OUT out
  exit-address-family
!
ip prefix-list BGP-OUT seq 10 permit $ONPREM_CIDR
!
route-map ALLOW-OUT permit 10
  match ip address prefix-list BGP-OUT
!
route-map ALLOW-IN permit 100
!
interface vti1
  ip address $CPE_BGP_PEER_IP_1
  no shutdown
  exit
interface vti2
  ip address $CPE_BGP_PEER_IP_2
  no shutdown
  exit
exit 
EOF

# enable and start frr
sudo systemctl status frr
sudo systemctl restart frr

exit 0