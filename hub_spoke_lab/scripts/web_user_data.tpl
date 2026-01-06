#!/bin/sh -x

# Common web instance bootstrap
sudo apt-get update
sudo apt-get install -y apache2
sudo tee /var/www/html/index.html > /dev/null <<EOF
<html><body><h1>${TITLE}</h1></body></html>
EOF
sudo systemctl enable apache2
sudo systemctl start apache2
