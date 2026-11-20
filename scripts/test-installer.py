"""Isolated actual-ash installer fixture; never touches a router or real /etc."""
import hashlib
import os
import json
from pathlib import Path
import subprocess
import tempfile

source = Path('installer.sh').read_text()
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
        'uci': 'echo 192.168.80.1',
        'netstat': 'echo "tcp 0 0 127.0.0.1:22 0.0.0.0:* LISTEN"',
        'dropbearkey': 'exit 0',
    }
    for name, command in commands.items():
        put('bin/' + name, '#!/bin/sh\n' + command + '\n')
    for name, text in {
        'etc/openwrt_release': 'test', 'sbin/procd': '',
        'etc/rc.common': '#!/bin/sh\nexit 0\n', 'etc/init.d/dropbear': '',
        'etc/config/dropbear': 'existing config',
        'etc/rc.local': '# preserve this\nexit 0\n',
        'etc/passwd': f'root:x:0:0:root:{root}/root:/bin/sh\n',
        'etc/dropbear/authorized_keys': 'existing admin key\n',
        'root/.ssh/known_hosts': 'existing host key\n',
    }.items():
        put(name, text)
    substitutions = {'PROFILE': 'city', 'PORT': '18581', 'RELAY_HOST': '176.124.198.201',
                     'HOST': '176.124.198.201 ssh-ed25519 TEST', 'ADMIN': 'ssh-ed25519 ADMIN',
                     'KEY_OCTAL': ''.join('\\0%03o' % byte for byte in key)}
    template = source
    for name, value in substitutions.items():
        template = template.replace('@@' + name + '@@', value)
    assert '@@' not in template
    for old, new in [('/usr/bin/dbclient', str(bindir/'dbclient')),
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
    assert apply_bypass().returncode != 0
    assert json.loads(state.read_text())['writes'] == 0
    (root/'etc/quiet-lantern/installed').write_text('dacha\n')
    assert run().returncode != 0
    (root/'etc/quiet-lantern/installed').write_text('city\n')
    put('bin/netstat', '#!/bin/sh\nexit 0\n')
    assert run().returncode != 0
print('Actual BusyBox ash: install, binary reconstruction, preserved config/keys, repeat no-op, profile mismatch and missing listener passed.')
print('Exclusion fixture: only relay TCP/22 in both known chains, idempotence, recreation and unknown-table refusal passed.')
