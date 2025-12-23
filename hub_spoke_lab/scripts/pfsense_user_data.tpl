#!/bin/sh
set -e

# Template-injected variables
PFSENSE_ADMIN_PASSWORD="${PFSENSE_ADMIN_PASSWORD}"
CARP_PASSWORD="${CARP_PASSWORD}"
WAN_IF="${WAN_IF}"
TRUST_IF="${TRUST_IF}"
WAN_VIP="${WAN_VIP}"
TRUST_VIP="${TRUST_VIP}"
VHID="${VHID}"
ADV_SKEW="${ADV_SKEW}"
TRUST_PREFIXES="${TRUST_PREFIXES}"

echo "Starting pfSense bootstrap (template)"

HOSTNAME=$(hostname)
if echo "$HOSTNAME" | grep -qi "-a$"; then
  ADV_SKEW_LOCAL=$ADV_SKEW
else
  ADV_SKEW_LOCAL=100
fi

echo "Waiting for pfSsh.php..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if [ -x /usr/local/sbin/pfSsh.php ]; then
    break
  fi
  sleep 5
done

if [ ! -x /usr/local/sbin/pfSsh.php ]; then
  echo "pfSsh.php not found; aborting bootstrap." >&2
  exit 1
fi

cat <<'PHP' > /tmp/pfsense_bootstrap.php
<?php
require_once('/etc/inc/config.inc');
global $config;

function vip_exists($if, $subnet) {
  global $config;
  if (!isset($config['virtualip']['vip'])) return false;
  foreach ($config['virtualip']['vip'] as $v) {
    if ($v['interface'] == $if && $v['subnet'] == $subnet . '/32') return true;
  }
  return false;
}

function add_vip_if_missing($if, $subnet, $vhid, $advskew, $passwd) {
  global $config;
  if (vip_exists($if, $subnet)) return;
  if (!isset($config['virtualip']['vip'])) $config['virtualip']['vip'] = array();
  $vip = array();
  $vip['mode'] = 'carp';
  $vip['interface'] = $if;
  $vip['subnet'] = $subnet . '/32';
  $vip['vhid'] = $vhid;
  $vip['advskew'] = $advskew;
  $vip['password'] = $passwd;
  $config['virtualip']['vip'][] = $vip;
}

function user_exists($username) {
  global $config;
  if (!isset($config['system']['user'])) return false;
  foreach ($config['system']['user'] as $u) {
    if ($u['name'] == $username) return true;
  }
  return false;
}

function add_admin_user($username, $password) {
  global $config;
  if (user_exists($username)) return;
  if (!isset($config['system']['user'])) $config['system']['user'] = array();
  $u = array();
  $u['name'] = $username;
  $u['password'] = crypt($password);
  $u['descr'] = 'Lab admin user';
  $u['priv'] = array();
  $config['system']['user'][] = $u;
}

function add_filter_rule($if, $descr, $src, $dst, $action='pass') {
  global $config;
  if (!isset($config['filter']['rule'])) $config['filter']['rule'] = array();
  $r = array();
  $r['interface'] = $if;
  $r['descr'] = $descr;
  $r['type'] = $action;
  $r['protocol'] = 'any';
  $r['source'] = array('network' => $src);
  $r['destination'] = array('network' => $dst);
  $config['filter']['rule'][] = $r;
}

function add_outbound_nat_rule($interface, $source_network) {
  global $config;
  if (!isset($config['nat']['rule'])) $config['nat']['rule'] = array();
  $n = array();
  $n['interface'] = $interface;
  $n['source'] = array('network' => $source_network);
  $n['target'] = '=interface';
  $config['nat']['rule'][] = $n;
}

function add_static_route($network, $interface) {
  global $config;
  if (!isset($config['staticroutes']['route'])) $config['staticroutes']['route'] = array();
  $r = array();
  $r['network'] = $network;
  $r['gateway'] = '';
  $r['interface'] = $interface;
  $config['staticroutes']['route'][] = $r;
}

$wan_if = getenv('WAN_IF');
$trust_if = getenv('TRUST_IF');
$wan_vip = getenv('WAN_VIP');
$trust_vip = getenv('TRUST_VIP');
$vhid = getenv('VHID');
$advskew = getenv('ADV_SKEW');
$carp_pass = getenv('CARP_PASSWORD');
$admin_pass = getenv('PFSENSE_ADMIN_PASSWORD');
$trust_prefixes = getenv('TRUST_PREFIXES');

if (!$wan_if || !$trust_if || !$wan_vip || !$trust_vip || !$vhid) {
  echo "Missing required env vars\n";
  exit(1);
}

add_vip_if_missing($wan_if, $wan_vip, $vhid, $advskew, $carp_pass);
add_vip_if_missing($trust_if, $trust_vip, $vhid, $advskew, $carp_pass);

if ($admin_pass) {
  add_admin_user('lab-admin', $admin_pass);
}

$config['nat']['outbound'] = 'manual';

$tns = preg_split('/\s+/', trim($trust_prefixes));
foreach ($tns as $tn) {
  add_filter_rule($trust_if, 'allow_trust_' . $tn, $tn, $tn, 'pass');
}

add_filter_rule($trust_if, 'allow_egress_trust_to_untrust', 'any', 'any', 'pass');

$deny = array();
$deny['interface'] = 'lan';
$deny['descr'] = 'deny_all';
$deny['type'] = 'block';
$deny['protocol'] = 'any';
$deny['source'] = array('network' => 'any');
$deny['destination'] = array('network' => 'any');
$config['filter']['rule'][] = $deny;

foreach ($tns as $tn) {
  add_outbound_nat_rule($wan_if, $tn);
}

foreach ($tns as $tn) {
  add_static_route($tn, $trust_if);
}

write_config();
filter_configure();
exec('/sbin/sh /etc/rc.d/routing restart 2>&1');
echo "Bootstrap complete\n";
?>
PHP

export WAN_IF TRUST_IF WAN_VIP TRUST_VIP VHID ADV_SKEW CARP_PASSWORD PFSENSE_ADMIN_PASSWORD TRUST_PREFIXES

/usr/local/sbin/pfSsh.php /tmp/pfsense_bootstrap.php || { echo "pfSsh.php execution failed" >&2; exit 1; }

echo "pfSense bootstrap applied; rebooting to ensure CARP and rules take effect"
shutdown -r now
