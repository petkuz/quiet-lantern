"""Isolated actual-ash installer fixture; never touches a router or real /etc."""
import hashlib
import os
import json
import signal
import time
import sys
from pathlib import Path
import subprocess
import tempfile

source = Path('installer.sh').read_text()
profile = sys.argv[1] if len(sys.argv) > 1 else 'city'
assert profile in ['city', 'dacha', 'home']
lan = '192.168.1.1' if profile == 'home' else '192.168.80.1'
port = {'city': '18581', 'dacha': '18582', 'home': '18584'}[profile]
other = 'dacha' if profile != 'dacha' else 'city'
assert 'base64' not in source
key = bytes(range(256))
with tempfile.TemporaryDirectory(prefix='ql-ash-') as directory:
    root = Path(directory)
    bindir = root / 'bin'
    bindir.mkdir()
    def put(name, text):
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        target.chmod(0o700)
    commands = {
        'id': 'echo 0',
        'logger': f'echo "$*" >> {root}/log',
        'dbclient': 'echo BatchMode StrictHostKeyChecking ExitOnForwardFailure',
        'uci': 'echo ' + lan,
        'netstat': 'echo "tcp 0 0 127.0.0.1:22 0.0.0.0:* LISTEN"',
        'dropbearkey': 'exit 0',
    }
    for name, command in commands.items():
        put('bin/' + name, '#!/bin/sh\n' + command + '\n')
    for name, text in {
        'etc/openwrt_release': 'test', 'sbin/procd': '',
        'etc/rc.common': f'#!/bin/sh\necho "$*" >> {root}/service-actions\nexit 0\n', 'etc/init.d/dropbear': '',
        'etc/config/dropbear': 'existing config',
        'etc/rc.local': '# preserve this\nexit 0\n',
        'etc/passwd': f'root:x:0:0:root:{root}/root:/bin/sh\n',
        'etc/dropbear/authorized_keys': 'existing admin key\n',
        'root/.ssh/known_hosts': 'existing host key\n',
    }.items():
        put(name, text)
    substitutions = {'PROFILE': profile, 'PORT': port, 'LAN': lan, 'RELAY_HOST': '176.124.198.201',
                     'HOST': '176.124.198.201 ssh-ed25519 TEST', 'ADMIN': 'ssh-ed25519 ADMIN',
                     'KEY_OCTAL': ''.join('\\0%03o' % byte for byte in key)}
    template = source
    for name, value in substitutions.items():
        template = template.replace('@@' + name + '@@', value)
    assert '@@' not in template
    for old, new in [('/usr/bin/dbclient', str(bindir/'dbclient')),
                     ('$(id -u)', '$(' + str(bindir/'id') + ' -u)'),
                     ('logger -t quiet-lantern', str(bindir/'logger') + ' -t quiet-lantern'),
                     ('netstat -lnt', str(bindir/'netstat') + ' -lnt'),
                     ('/etc/', str(root/'etc')+'/'), ('/root', str(root/'root')),
                     ('/sbin/procd', str(root/'sbin/procd')),
                     ('/tmp/quiet-lantern-install.lock', str(root/'lock'))]:
        template = template.replace(old, new)
    put('install.sh', template)
    env = dict(os.environ, PATH=str(bindir)+':/usr/bin:/bin')
    def run():
        return subprocess.run(['busybox', 'ash', str(root/'install.sh')], env=env, capture_output=True)
    subprocess.run(['busybox', 'ash', '-n', str(root/'install.sh')], check=True)
    result = run()
    assert result.returncode == 0, (result.stderr, (root/'log').read_text() if (root/'log').exists() else 'no log')
    assert (root/'etc/quiet-lantern/tunnel.key').read_bytes() == key
    assert (root/'etc/rc.local').read_text() == '# preserve this\nexit 0\n'
    assert (root/'etc/dropbear/authorized_keys').read_text().startswith('existing admin key\n')
    assert 'HOME=/root' not in (root/'etc/init.d/quiet-lantern').read_text()  # fixture home substitution
    before = {p: hashlib.sha256(p.read_bytes()).digest() for p in root.rglob('*') if p.is_file()}
    assert run().returncode == 0
    assert before == {p: hashlib.sha256(p.read_bytes()).digest() for p in before}
    protected = [root/'etc/quiet-lantern/tunnel.key', root/'etc/dropbear/authorized_keys', root/'root/.ssh/known_hosts', root/'etc/rc.local']
    protected += list((root/'etc/quiet-lantern').glob('*.before'))
    original = {p: p.read_bytes() for p in protected}
    # Original v3 installs had no version marker. Upgrade only the three owned scripts.
    (root/'etc/quiet-lantern/version').unlink()
    put('etc/quiet-lantern/bypass.sh', '#!/bin/sh\n# old v3 bypass\nexit 1\n')
    put('etc/quiet-lantern/run.sh', '#!/bin/sh\n# old v3 worker\nexit 1\n')
    old_owned = {name: (root/name).read_bytes() for name in ['etc/quiet-lantern/bypass.sh', 'etc/quiet-lantern/run.sh', 'etc/init.d/quiet-lantern']}
    assert run().returncode == 0
    assert (root/'etc/quiet-lantern/version').read_text() == '4\n'
    assert all(p.read_bytes() == data for p, data in original.items())
    for name, data in old_owned.items():
        backup = 'service' if name.endswith('init.d/quiet-lantern') else Path(name).name
        assert (root/'etc/quiet-lantern/owned-before-v4'/backup).read_bytes() == data
    assert [line.split()[-1] for line in (root/'service-actions').read_text().splitlines()][-2:] == ['stop', 'start']
    snapshot = {p: p.read_bytes() for p in root.rglob('*') if p.is_file()}
    assert run().returncode == 0
    assert all(p.read_bytes() == data for p, data in snapshot.items())
    (root/'etc/quiet-lantern/version').write_text('3\n')
    put('etc/quiet-lantern/disabled', '')
    snapshot = {p: p.read_bytes() for p in root.rglob('*') if p.is_file()}
    assert run().returncode == 0
    assert all(p.read_bytes() == data for p, data in snapshot.items())
    (root/'etc/quiet-lantern/disabled').unlink()
    # Exercise the exact installed exclusion helper without touching host nftables.
    state = root/'nft-state.json'
    state.write_text(json.dumps({'mode': 'known', 'rules': [], 'writes': 0}))
    mock = '''#!/usr/bin/python3
import json, sys
from pathlib import Path
p = Path(STATE)
s = json.loads(p.read_text())
a = sys.argv[1:]
if 'list' in a:
    if s['mode'] == 'absent': sys.exit(1)
    if 'table' in a: print('table inet v2raya {}')
    elif 'set' in a: print('type ipv4_addr;')
    else:
        chain = a[-1]
        print('jump tp_rule' if chain == 'tp_out' else ('ip daddr @whitelist return' if s['mode'] == 'known' else 'unknown routing'))
        for rule in s['rules']:
            if 'v2raya '+chain+' ' in rule: print(rule)
elif '-f' in a:
    rules = [r for r in sys.stdin.read().splitlines() if r]
    for rule in rules:
        assert rule in ['insert rule inet v2raya '+c+' ip daddr 176.124.198.201 tcp dport 22 counter meta mark set 0 ct mark set 0 return comment "quiet-lantern-relay"' for c in ['tp_out','tp_rule']]
    if '-c' not in a:
        s['rules'] += rules
        s['writes'] += 1
        p.write_text(json.dumps(s))
else: sys.exit(1)
'''.replace('STATE', repr(str(state)))
    put('bin/nft', mock)
    bypass = root/'etc/quiet-lantern/bypass.sh'
    def apply_bypass():
        return subprocess.run(['busybox', 'ash', str(bypass)], env=env, capture_output=True)
    assert apply_bypass().returncode == 0
    assert len(json.loads(state.read_text())['rules']) == 2
    assert apply_bypass().returncode == 0
    assert json.loads(state.read_text())['writes'] == 1
    state.write_text(json.dumps({'mode': 'known', 'rules': [], 'writes': 0}))
    assert apply_bypass().returncode == 0
    assert len(json.loads(state.read_text())['rules']) == 2
    state.write_text(json.dumps({'mode': 'unknown', 'rules': [], 'writes': 0}))
    result = apply_bypass()
    assert result.returncode == 0 and result.stdout.strip() == b'fallback'
    assert json.loads(state.read_text())['writes'] == 0
    # The real ash worker must try SSH even with unknown rules, without changing them.
    put('bin/dbclient', f'#!/bin/sh\nif [ "$1" = -o ] && [ "$2" = help ]; then echo BatchMode StrictHostKeyChecking ExitOnForwardFailure; exit 0; fi\necho attempt >> {root}/ssh-attempts\n/bin/sleep 60\n')
    worker = root/'worker-test.sh'
    worker.write_text((root/'etc/quiet-lantern/run.sh').read_text().replace('sleep 15', '/bin/sleep 0.03'))
    process = subprocess.Popen(['busybox', 'ash', str(worker)], env=env, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            if (root/'ssh-attempts').exists(): break
            time.sleep(.02)
        assert (root/'ssh-attempts').exists()
        time.sleep(.15)
        assert json.loads(state.read_text())['writes'] == 0
        warning = 'No supported VPN exclusion; trying SSH over existing routing without changing VPN rules'
        assert (root/'log').read_text().count(warning) == 1
    finally:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=3)
    (root/'etc/quiet-lantern/installed').write_text(other+'\n')
    assert run().returncode != 0
    (root/'etc/quiet-lantern/installed').write_text(profile+'\n')
    put('bin/netstat', '#!/bin/sh\nexit 0\n')
    assert run().returncode != 0
print('Actual BusyBox ash: fresh install, v3 upgrade with preserved keys/backups, repeat no-op, disabled state, profile mismatch and missing listener passed.')
print('Routing fixture: exact known-chain rules, recreation, unknown-table SSH attempt without mutation and bounded warning passed.')
