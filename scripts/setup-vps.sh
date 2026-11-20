#!/bin/sh
# Run as root on the chosen VPS. No VPN or firewall changes.
set -eu
base=/root/quiet-lantern
test ! -e "$base" || { echo 'Existing setup: inspect manually'; exit 1; }
test ! -e /etc/ssh/sshd_config.d/60-quiet-lantern.conf || exit 1
for profile in city dacha; do
  ! getent passwd "ql-$profile" >/dev/null || exit 1
done
! ss -H -lnt | awk '{print $4}' | grep -Eq ':1858[12]$' || exit 1
umask 077
mkdir "$base"
cp -a /etc/ssh/sshd_config "$base/sshd_config.before"
cp -a /etc/ssh/sshd_config.d "$base/sshd_config.d.before"
cd "$base"
apt-get download dropbear-bin >/dev/null
dpkg-deb -x ./dropbear-bin*.deb tools
apt-get download libtomcrypt1 libtommath1 >/dev/null
for package in libtom*.deb; do dpkg-deb -x "$package" tools; done
export LD_LIBRARY_PATH="$base/tools/usr/lib/x86_64-linux-gnu"
for profile in city dacha; do
  user=ql-$profile
  ! getent passwd "$user" >/dev/null || exit 1
  useradd -m -s /usr/sbin/nologin "$user"
  # Locked passwords can reject public-key auth on some systems; random unusable hash.
  usermod -p '*' "$user"
  mkdir -m 700 /home/$user/.ssh
  tools/usr/bin/dropbearkey -t ed25519 -f "$profile.key" > "$profile.pub" 2>/dev/null
  port=18581
  test "$profile" = city || port=18582
  pub=$(sed -n '/^ssh-ed25519 /p' "$profile.pub")
  test -n "$pub"
  printf 'restrict,port-forwarding,permitlisten="127.0.0.1:%s",command="/bin/false" %s\n' "$port" "$pub" > /home/$user/.ssh/authorized_keys
  chown -R "$user:$user" /home/$user/.ssh
  chmod 600 /home/$user/.ssh/authorized_keys
  cat >> /etc/ssh/sshd_config.d/60-quiet-lantern.conf <<EOF
Match User $user
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AllowTcpForwarding remote
    AllowStreamLocalForwarding no
    PermitListen 127.0.0.1:$port
    PermitOpen none
    GatewayPorts no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
    PermitTunnel no
    MaxSessions 0
    ForceCommand /bin/false
Match all
EOF
done
if ! /usr/sbin/sshd -t; then
  rm /etc/ssh/sshd_config.d/60-quiet-lantern.conf
  exit 1
fi
systemctl reload ssh
echo 'Restricted accounts installed; no router connected.'
