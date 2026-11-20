# quiet-lantern

Small Russian mobile helper published at https://petkuz.github.io/quiet-lantern/ using free GitHub Pages. No external browser dependencies, analytics, or router password collection.

`docs/` is the complete deployable artifact. `payload.json` contains authenticated ciphertext, never plaintext bootstrap credentials. The QR contains only the canonical HTTPS URL. Visiting or unlocking does not register a device or install anything.

Encryption: WebCrypto PBKDF2-HMAC-SHA256, 900,000 iterations, random 16-byte salt, AES-256-GCM with random 12-byte IV. A predictable numeric password remains vulnerable to offline guessing. This is not strong authentication; a discreet name and noindex are not security controls. Anyone holding the password can extract the dedicated tunnel identities. Those identities permit only their assigned VPS loopback listener, never a shell, local forwarding, public listener, agent, or PTY. They are reusable, not one-time enrollment. Revoke/rotate after suspected disclosure; old Git history retains old ciphertext.

Build locally on Windows: `node scripts/build.mjs`. Required private inputs live outside Git under `%LOCALAPPDATA%/quiet-lantern/` and the administrator public key stays under the local SSH directory. Never copy private inputs into the repository or Actions. `npm test` tests authenticated encryption and clipboard sequencing. `node scripts/test-installer.mjs` runs on a POSIX system for installer no-op and fail-closed checks. The VPS test is an explicit administrative operation, not a CI job.

Installer requires compatible OpenWrt/procd, Dropbear client with BatchMode/StrictHostKeyChecking/ExitOnForwardFailure, IPv4 LAN 192.168.80.1 and an existing IPv4 SSH listener accepting loopback on port 22. It does not install packages, alter firewall/network/VPN configuration, or enable router password authentication. Unsupported firmware stops and logs to `quiet-lantern`. Existing rc.local text must be preserved, with the block inserted before its final `exit 0`. It adds a persistent procd service and preserves existing authorized keys. Initial setup backs up affected files under `/etc/quiet-lantern/`; subsequent rc.local executions are no-ops. An incomplete installation stops for manual inspection.

VPS restrictions follow [OpenSSH's forwarding controls](https://man.openbsd.org/sshd_config). Dropbear host verification uses [HOME/.ssh/known_hosts](https://github.com/mkj/dropbear/blob/master/src/cli-kex.c); the service explicitly sets HOME=/root.
A small personal setup helper
