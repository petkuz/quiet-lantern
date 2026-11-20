#!/bin/sh
# Template: credentials are substituted locally and only published encrypted.
(
set -eu
umask 077
fail() { logger -t quiet-lantern "$1"; exit 1; }
[ "$(id -u)" = 0 ] || exit 1
[ -f /etc/openwrt_release ] && [ -x /sbin/procd ] && [ -x /etc/rc.common ] || fail 'Unsupported firmware'
[ -x /usr/bin/dbclient ] || fail 'Dropbear client missing; ask Petr'
for option in BatchMode StrictHostKeyChecking ExitOnForwardFailure; do
  dbclient -o help 2>&1 | grep -q "$option" || fail 'Required SSH option missing'
done
dbclient -o help 2>&1 | grep -q StrictHostKeyChecking || fail 'Client cannot pin host key'
dbclient -o help 2>&1 | grep -q ExitOnForwardFailure || fail 'Client lacks forwarding safety'
command -v base64 >/dev/null || fail 'base64 missing'
command -v dropbearkey >/dev/null || fail 'dropbearkey missing'
[ -f /etc/config/dropbear ] && [ -d /etc/dropbear ] || fail 'Dropbear server missing'
uci -q get network.lan.ipaddr | grep -qx '192.168.80.1' || fail 'Unexpected LAN address; ask Petr'
[ -x /etc/init.d/dropbear ] || fail 'SSH server missing'
command -v netstat >/dev/null || fail 'Cannot verify SSH listener'
netstat -lnt 2>/dev/null | awk '$4 == "127.0.0.1:22" || $4 == "0.0.0.0:22" { found=1 } END { exit !found }' || fail 'No IPv4 loopback SSH listener on port 22; ask Petr'
[ "$(awk -F: '$1=="root" {print $6}' /etc/passwd)" = /root ] || fail 'Unsupported root home'
[ ! -e /etc/quiet-lantern/disabled ] || exit 0
if [ -f /etc/quiet-lantern/installed ]; then
  [ "$(cat /etc/quiet-lantern/installed)" = '@@PROFILE@@' ] || fail 'Different profile already installed'
  exit 0
fi
mkdir /tmp/quiet-lantern-install.lock 2>/dev/null || exit 0
trap 'rmdir /tmp/quiet-lantern-install.lock' EXIT
[ ! -e /etc/quiet-lantern ] || fail 'Incomplete installation; ask Petr'
mkdir -m 700 /etc/quiet-lantern
cp -p /etc/rc.local /etc/quiet-lantern/rc.local.before
cp -p /etc/config/dropbear /etc/quiet-lantern/dropbear.before
[ ! -f /etc/dropbear/authorized_keys ] || cp -p /etc/dropbear/authorized_keys /etc/quiet-lantern/authorized_keys.before
mkdir -p /root/.ssh
chmod 700 /root/.ssh
[ ! -f /root/.ssh/known_hosts ] || cp -p /root/.ssh/known_hosts /etc/quiet-lantern/known_hosts.before
if [ -f /root/.ssh/known_hosts ] && grep -q '178.236.240.153' /root/.ssh/known_hosts; then
  grep -Fqx '@@HOST@@' /root/.ssh/known_hosts || fail 'VPS host key conflict'
else
  printf '\n%s\n' '@@HOST@@' >> /root/.ssh/known_hosts
fi
chmod 600 /root/.ssh/known_hosts
printf '%s' '@@KEY@@' | base64 -d > /etc/quiet-lantern/tunnel.key
dropbearkey -y -f /etc/quiet-lantern/tunnel.key >/dev/null 2>&1 || fail 'Invalid key'
touch /etc/dropbear/authorized_keys
grep -Fqx '@@ADMIN@@' /etc/dropbear/authorized_keys || printf '\n%s\n' '@@ADMIN@@' >> /etc/dropbear/authorized_keys
chmod 600 /etc/dropbear/authorized_keys /etc/quiet-lantern/tunnel.key
cat > /etc/init.d/quiet-lantern <<'QL_SERVICE'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
  [ ! -e /etc/quiet-lantern/disabled ] || return 0
  procd_open_instance
  procd_set_param env HOME=/root
  procd_set_param command /usr/bin/dbclient -N -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -K 30 -I 120 -i /etc/quiet-lantern/tunnel.key -R 127.0.0.1:@@PORT@@:127.0.0.1:22 ql-@@PROFILE@@@178.236.240.153
  procd_set_param respawn 3600 15 0
  procd_set_param stdout 0
  procd_set_param stderr 1
  procd_close_instance
}
QL_SERVICE
chmod 700 /etc/init.d/quiet-lantern
printf '%s\n' '@@PROFILE@@' > /etc/quiet-lantern/installed
/etc/init.d/quiet-lantern enable
/etc/init.d/quiet-lantern start
logger -t quiet-lantern 'Installed; ask Petr to verify connection'
) </dev/null
