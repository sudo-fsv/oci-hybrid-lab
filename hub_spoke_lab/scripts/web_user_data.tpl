#!/bin/bash
# Common web instance bootstrap
apt-get update
apt-get install -y apache2
cat > /var/www/html/index.html <<EOF
<html><body><h1>${TITLE}</h1></body></html>
EOF
systemctl enable apache2
systemctl start apache2
