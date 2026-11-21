# Home can use any valid configured LAN IPv4 address, including CIDR notation.
lan=$(uci -q get network.lan.ipaddr) || fail 'LAN address missing; ask Petr'
printf '%s\n' "$lan" | awk '
function valid(value, prefix, octet, count, j) {
  count=split(value,prefix,"/")
  if (count>2 || (count==2 && (prefix[2] !~ /^[0-9]+$/ || prefix[2]+0>32))) return 0
  if (split(prefix[1],octet,".")!=4) return 0
  for (j=1;j<=4;j++) if (octet[j] !~ /^[0-9]+$/ || octet[j]+0>255) return 0
  return octet[1]+0>0 && octet[1]+0!=127 && octet[1]+0<224
}
{ for (i=1;i<=NF;i++) if (valid($i)) found=1 }
END { exit !found }
' || fail 'Invalid configured LAN address; ask Petr'
