#!/bin/sh
set -eu
cd /root/quiet-lantern
export LD_LIBRARY_PATH="$PWD/tools/usr/lib/x86_64-linux-gnu"
export HOME="$PWD/test-home"
mkdir -p "$HOME/.ssh"
printf '178.236.240.153 %s\n' "$(cut -d ' ' -f 1,2 /etc/ssh/ssh_host_ed25519_key.pub)" > "$HOME/.ssh/known_hosts"
client="$PWD/tools/usr/bin/dbclient"
for profile in city dacha; do
  port=18581; test "$profile" = city || port=18582
  "$client" -N -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -K 30 -I 120 -i "$profile.key" -R 127.0.0.1:$port:127.0.0.1:22 ql-$profile@178.236.240.153 >test-$profile.log 2>&1 &
  pid=$!
  sleep 2
  kill -0 "$pid"
  ss -lnt | grep "127.0.0.1:$port "
  kill "$pid"
  wait "$pid" || true
  if timeout 5 "$client" -N -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -i "$profile.key" -R 127.0.0.1:18599:127.0.0.1:22 ql-$profile@178.236.240.153 >test-denied.log 2>&1; then exit 1; fi
  grep -qi 'forward.*fail\|failed.*forward' test-denied.log
done
if ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$HOME/.ssh/known_hosts" -o IdentitiesOnly=yes -i city.openssh ql-city@178.236.240.153 true >test-shell.log 2>&1; then exit 1; fi
grep -qi 'administratively prohibited\|open failed' test-shell.log
echo 'Both loopback forwards succeeded; unauthorized ports and shell denied.'
