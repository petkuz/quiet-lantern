// The only permitted change to the protected father baseline for release 7.
export function withoutLegacyIdleTimeout(source) {
  return source.replace(' -K 30 -I 120 -i /etc/quiet-lantern/tunnel.key', ' -K 30 -i /etc/quiet-lantern/tunnel.key');
}
