#!/bin/sh -x

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

# Common web instance bootstrap
sudo apt-get update
sudo apt-get install -y apache2
sudo tee /var/www/html/index.html > /dev/null <<EOF
<html><body><h1>${TITLE}</h1></body></html>
EOF
sudo systemctl enable apache2
sudo systemctl start apache2

# Allow load balancer health checks from the private subnet (allow TCP/80)
LB_PRIV_SUBNET_CIDR="${LB_PRIV_SUBNET_CIDR}"
ONPREM_CIDR="${ONPREM_CIDR}"
# allow LB private subnet
if [ -n "$LB_PRIV_SUBNET_CIDR" ]; then
	sudo iptables -C INPUT -p tcp -s "$LB_PRIV_SUBNET_CIDR" --dport 80 -j ACCEPT 2>/dev/null || \
		sudo iptables -I INPUT 1 -p tcp -s "$LB_PRIV_SUBNET_CIDR" --dport 80 -j ACCEPT
fi
# allow onprem CIDR
if [ -n "$ONPREM_CIDR" ]; then
	sudo iptables -C INPUT -p tcp -s "$ONPREM_CIDR" --dport 80 -j ACCEPT 2>/dev/null || \
		sudo iptables -I INPUT 1 -p tcp -s "$ONPREM_CIDR" --dport 80 -j ACCEPT
fi
# persist iptables rules if iptables-persistent is available
if command -v netfilter-persistent >/dev/null 2>&1; then
	sudo netfilter-persistent save || true
elif [ -d /etc/iptables ]; then
	sudo sh -c "iptables-save > /etc/iptables/rules.v4" || true
fi
