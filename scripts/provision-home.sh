#!/bin/sh
# Add only the home identity; public key supplied as a file, never a private key.
set -eu
umask 077
pubfile=${1:?public key file required}
! getent passwd ql-home >/dev/null || exit 1
! ss -H -lnt | awk '{print $4}' | grep -Eq ':18584$' || exit 1
test ! -e /etc/ssh/sshd_config.d/61-quiet-lantern-home.conf || exit 1
backup=/root/quiet-lantern/provision-home-before
test ! -e "$backup" || exit 1
mkdir -m 700 "$backup"
cp -a /etc/ssh/sshd_config "$backup/sshd_config"
cp -a /etc/ssh/sshd_config.d "$backup/sshd_config.d"
sha256sum /home/ql-city/.ssh/authorized_keys /home/ql-dacha/.ssh/authorized_keys /root/quiet-lantern/city.key /root/quiet-lantern/dacha.key /etc/ssh/sshd_config.d/60-quiet-lantern.conf /etc/ssh/sshd_config.d/70-father-relay-keepalive.conf > "$backup/protected.sha256"
pub=$(cat "$pubfile")
case "$pub" in 'ssh-ed25519 '*) ;; *) exit 1;; esac
ssh-keygen -l -f "$pubfile" >/dev/null
useradd -m -s /usr/sbin/nologin ql-home
usermod -p '*' ql-home
mkdir -m 700 /home/ql-home/.ssh
printf 'restrict,port-forwarding,permitlisten="127.0.0.1:18584",command="/bin/false" %s\n' "$pub" > /home/ql-home/.ssh/authorized_keys
chmod 600 /home/ql-home/.ssh/authorized_keys
chown -R ql-home:ql-home /home/ql-home/.ssh
cat > /etc/ssh/sshd_config.d/61-quiet-lantern-home.conf <<'EOF'
Match User ql-home
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AllowTcpForwarding remote
    AllowStreamLocalForwarding no
    PermitListen 127.0.0.1:18584
    PermitOpen none
    GatewayPorts no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
    PermitTunnel no
    MaxSessions 0
    ForceCommand /bin/false
    ClientAliveInterval 30
    ClientAliveCountMax 3
Match all
EOF
if ! /usr/sbin/sshd -t; then
  rm /etc/ssh/sshd_config.d/61-quiet-lantern-home.conf
  exit 1
fi
sha256sum -c "$backup/protected.sha256" >/dev/null
systemctl reload ssh
sha256sum -c "$backup/protected.sha256" >/dev/null
echo 'Home-only relay provisioned; protected father files unchanged.'
