import fs from 'node:fs';
import path from 'node:path';
import {derive,iterations} from '../docs/crypto.js';
import {encodeKeyOctal} from './key-encoding.mjs';
const relay=JSON.parse(fs.readFileSync('relay.json','utf8'));
if(!/^\d{1,3}(\.\d{1,3}){3}$/.test(relay.host)) throw Error('Invalid relay host');
const dir=path.join(process.env.LOCALAPPDATA,'quiet-lantern');
const password=fs.readFileSync(path.join(dir,'page-password'),'utf8').trim();
if(!password) throw Error('Missing password');
const host=relay.host+' '+fs.readFileSync(path.join(dir,'private/vps-host.pub'),'utf8').trim().split(/\s+/).slice(0,2).join(' ');
const admin=fs.readFileSync(path.join(process.env.USERPROFILE,'.ssh/id_ed25519_openwrt.pub'),'utf8').trim().split(/\s+/).slice(0,2).join(' ');
const template=fs.readFileSync('scripts/installer.sh','utf8').replace(/\r\n/g,'\n');
const profiles={};
for(const [profile,port] of Object.entries(relay.profiles)) {
 if(!['city','dacha','home'].includes(profile)||!Number.isInteger(port)||port<1024||port>65535||!/^192\.168\.\d+\.1$/.test(relay.lan[profile])) throw Error('Invalid relay profile');
 const key=encodeKeyOctal(fs.readFileSync(path.join(dir,'private',profile+'.key')));
 profiles[profile]=template.replaceAll('@@PROFILE@@',profile).replaceAll('@@PORT@@',String(port)).replaceAll('@@HOST@@',host).replaceAll('@@RELAY_HOST@@',relay.host).replaceAll('@@ADMIN@@',admin).replaceAll('@@KEY_OCTAL@@',key).replaceAll('@@LAN@@',relay.lan[profile]);
 if(/@@[A-Z_]+@@/.test(profiles[profile])) throw Error('Unresolved template');
 const baseline=path.join(dir,'private','compat-release4',profile+'-installer.sh');
 if(['city','dacha'].includes(profile)&&fs.existsSync(baseline)&&profiles[profile]!==fs.readFileSync(baseline,'utf8')) throw Error('Father compatibility changed');
 fs.writeFileSync(path.join(dir,'private',profile+'-installer.sh'),profiles[profile]);
}
const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
const key=await derive(password,salt,['encrypt']);
const data=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode(JSON.stringify(profiles)));
const b64=x=>Buffer.from(x).toString('base64');
fs.writeFileSync('docs/payload.json',JSON.stringify({version:1,iterations,salt:b64(salt),iv:b64(iv),data:b64(data)}));
console.log('Encrypted all profiles; no plaintext credentials written to public output.');
