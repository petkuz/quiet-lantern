#!/bin/sh
# Template: credentials are substituted locally and only published encrypted.
(
set -eu
umask 077
fail() { logger -t quiet-lantern "$1"; exit 1; }
[ "$(id -u)" = 0 ] || exit 1
if [ -f /etc/quiet-lantern/installed ]; then
  [ "$(cat /etc/quiet-lantern/installed)" = '@@PROFILE@@' ] || fail 'Different profile already installed'
fi
[ ! -e /etc/quiet-lantern/disabled ] || exit 0
if [ -f /etc/quiet-lantern/installed ] && [ -f /etc/quiet-lantern/version ] && [ "$(cat /etc/quiet-lantern/version)" = 4 ]; then
  exit 0
fi
[ -f /etc/openwrt_release ] && [ -x /sbin/procd ] && [ -x /etc/rc.common ] || fail 'Unsupported firmware'
[ -x /usr/bin/dbclient ] || fail 'Dropbear client missing; ask Petr'
for option in BatchMode StrictHostKeyChecking ExitOnForwardFailure; do
  dbclient -o help 2>&1 | grep -q "$option" || fail 'Required SSH option missing'
done
command -v dropbearkey >/dev/null || fail 'dropbearkey missing'
[ -f /etc/config/dropbear ] && [ -d /etc/dropbear ] || fail 'Dropbear server missing'
uci -q get network.lan.ipaddr | grep -qx '@@LAN@@' || fail 'Unexpected LAN address; ask Petr'
[ -x /etc/init.d/dropbear ] || fail 'SSH server missing'
command -v netstat >/dev/null || fail 'Cannot verify SSH listener'
netstat -lnt 2>/dev/null | awk '$4 == "127.0.0.1:22" || $4 == "0.0.0.0:22" { found=1 } END { exit !found }' || fail 'No IPv4 loopback SSH listener on port 22; ask Petr'
[ "$(awk -F: '$1=="root" {print $6}' /etc/passwd)" = /root ] || fail 'Unsupported root home'
mkdir /tmp/quiet-lantern-install.lock 2>/dev/null || exit 0
trap 'rmdir /tmp/quiet-lantern-install.lock' EXIT
upgrade=no
if [ -f /etc/quiet-lantern/installed ]; then
  upgrade=yes
  [ -f /etc/quiet-lantern/tunnel.key ] && [ -f /etc/quiet-lantern/bypass.sh ] &&
    [ -f /etc/quiet-lantern/run.sh ] && [ -f /etc/init.d/quiet-lantern ] || fail 'Incomplete installation; ask Petr'
  if [ ! -d /etc/quiet-lantern/owned-before-v4 ]; then
    mkdir -m 700 /etc/quiet-lantern/owned-before-v4
    cp -p /etc/quiet-lantern/bypass.sh /etc/quiet-lantern/owned-before-v4/bypass.sh
    cp -p /etc/quiet-lantern/run.sh /etc/quiet-lantern/owned-before-v4/run.sh
    cp -p /etc/init.d/quiet-lantern /etc/quiet-lantern/owned-before-v4/service
    touch /etc/quiet-lantern/owned-before-v4/complete
  fi
  [ -f /etc/quiet-lantern/owned-before-v4/complete ] || fail 'Incomplete update backup; ask Petr'
else
[ ! -e /etc/quiet-lantern ] || fail 'Incomplete installation; ask Petr'
mkdir -m 700 /etc/quiet-lantern
cp -p /etc/rc.local /etc/quiet-lantern/rc.local.before
cp -p /etc/config/dropbear /etc/quiet-lantern/dropbear.before
[ ! -f /etc/dropbear/authorized_keys ] || cp -p /etc/dropbear/authorized_keys /etc/quiet-lantern/authorized_keys.before
mkdir -p /root/.ssh
chmod 700 /root/.ssh
[ ! -f /root/.ssh/known_hosts ] || cp -p /root/.ssh/known_hosts /etc/quiet-lantern/known_hosts.before
if [ -f /root/.ssh/known_hosts ] && grep -Fq '@@RELAY_HOST@@' /root/.ssh/known_hosts; then
  grep -Fqx '@@HOST@@' /root/.ssh/known_hosts || fail 'VPS host key conflict'
else
  printf '\n%s\n' '@@HOST@@' >> /root/.ssh/known_hosts
fi
chmod 600 /root/.ssh/known_hosts
printf '%b' '@@KEY_OCTAL@@' > /etc/quiet-lantern/tunnel.key
dropbearkey -y -f /etc/quiet-lantern/tunnel.key >/dev/null 2>&1 || fail 'Invalid key'
touch /etc/dropbear/authorized_keys
grep -Fqx '@@ADMIN@@' /etc/dropbear/authorized_keys || printf '\n%s\n' '@@ADMIN@@' >> /etc/dropbear/authorized_keys
chmod 600 /etc/dropbear/authorized_keys /etc/quiet-lantern/tunnel.key
fi
stage=/etc/quiet-lantern/.update-4
mkdir -p "$stage"
cat > "$stage/bypass.sh" <<'QL_BYPASS'
#!/bin/sh
# Only the recognised v2rayA interception chains, only this relay's SSH traffic.
set -eu
fallback() { printf '%s\n' fallback; exit 0; }
if ! command -v nft >/dev/null || ! nft -n list table inet v2raya >/dev/null 2>&1; then
  if command -v pidof >/dev/null && pidof v2raya v2ray xray sing-box >/dev/null 2>&1; then
    fallback
  fi
  printf '%s\n' routing
  exit 0
fi
out=$(nft -n list chain inet v2raya tp_out 2>/dev/null) || fallback
rule=$(nft -n list chain inet v2raya tp_rule 2>/dev/null) || fallback
white=$(nft -n list set inet v2raya whitelist 2>/dev/null) || fallback
if ! printf '%s\n' "$out" | grep -q 'jump tp_rule' ||
   ! printf '%s\n' "$rule" | grep -q 'ip daddr @whitelist return' ||
   ! printf '%s\n' "$white" | grep -q 'type ipv4_addr'; then
  fallback
fi
rules=''
for chain in tp_out tp_rule; do
  current=$(nft -n list chain inet v2raya "$chain" 2>/dev/null) || fallback
  if printf '%s\n' "$current" | grep -Fq 'comment "quiet-lantern-relay"'; then
    printf '%s\n' "$current" | grep -F 'comment "quiet-lantern-relay"' | grep -Fq 'ip daddr @@RELAY_HOST@@ tcp dport 22' || fallback
  else
    rules="$rules
insert rule inet v2raya $chain ip daddr @@RELAY_HOST@@ tcp dport 22 counter meta mark set 0 ct mark set 0 return comment \"quiet-lantern-relay\""
  fi
done
if [ -n "$rules" ]; then
  printf '%s\n' "$rules" | nft -c -f - >/dev/null 2>&1 || fallback
  printf '%s\n' "$rules" | nft -f - >/dev/null 2>&1 || fallback
fi
printf '%s\n' managed
QL_BYPASS
cat > "$stage/run.sh" <<'QL_RUN'
#!/bin/sh
set -u
export HOME=/root
child=''
last_status=''
update_routing() {
  status=$(/etc/quiet-lantern/bypass.sh 2>/dev/null) || status=fallback
  if [ "$status" != "$last_status" ]; then
    case "$status" in
      managed) logger -t quiet-lantern 'Relay-only v2rayA exclusion active' ;;
      routing) logger -t quiet-lantern 'Trying SSH over existing routing' ;;
      *) logger -t quiet-lantern 'No supported VPN exclusion; trying SSH over existing routing without changing VPN rules' ;;
    esac
    last_status=$status
  fi
}
cleanup() {
  if [ -n "$child" ]; then kill "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; fi
}
trap 'exit 0' TERM INT
trap cleanup EXIT
while :; do
  update_routing
  /usr/bin/dbclient -N -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -K 30 -i /etc/quiet-lantern/tunnel.key -R 127.0.0.1:@@PORT@@:127.0.0.1:22 -l ql-@@PROFILE@@ @@RELAY_HOST@@ &
  child=$!
  while kill -0 "$child" 2>/dev/null; do
    sleep 15
    update_routing
  done
  cleanup
  child=''
  sleep 15
done
QL_RUN
cat > "$stage/service" <<'QL_SERVICE'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
  [ ! -e /etc/quiet-lantern/disabled ] || return 0
  procd_open_instance
  procd_set_param env HOME=/root
  procd_set_param command /etc/quiet-lantern/run.sh
  procd_set_param respawn 3600 15 0
  procd_set_param stdout 0
  procd_set_param stderr 1
  procd_close_instance
}
QL_SERVICE
for file in bypass.sh run.sh service; do
  sh -n "$stage/$file" || fail 'Invalid service script'
  chmod 700 "$stage/$file"
done
if [ "$upgrade" = yes ]; then /etc/init.d/quiet-lantern stop; fi
mv "$stage/bypass.sh" /etc/quiet-lantern/bypass.sh
mv "$stage/run.sh" /etc/quiet-lantern/run.sh
mv "$stage/service" /etc/init.d/quiet-lantern
rmdir "$stage"
chmod 700 /etc/init.d/quiet-lantern
if [ "$upgrade" = no ]; then
  printf '%s\n' '@@PROFILE@@' > /etc/quiet-lantern/installed
  /etc/init.d/quiet-lantern enable
fi
/etc/init.d/quiet-lantern start
printf '%s\n' 4 > /etc/quiet-lantern/version
logger -t quiet-lantern 'Version 4 installed; ask Petr to verify connection'
) </dev/null
