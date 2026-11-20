import fs from 'node:fs';
import path from 'node:path';
import {derive,iterations} from '../docs/crypto.js';
const dir=path.join(process.env.LOCALAPPDATA,'quiet-lantern');
const password=fs.readFileSync(path.join(dir,'page-password'),'utf8').trim();
if(!password) throw Error('Missing password');
const host='178.236.240.153 '+fs.readFileSync(path.join(dir,'private/vps-host.pub'),'utf8').trim().split(/\s+/).slice(0,2).join(' ');
const admin=fs.readFileSync(path.join(process.env.USERPROFILE,'.ssh/id_ed25519_openwrt.pub'),'utf8').trim().split(/\s+/).slice(0,2).join(' ');
const template=fs.readFileSync('scripts/installer.sh','utf8');
const profiles={};
for(const [profile,port] of [['city',18581],['dacha',18582]]) {
 const key=fs.readFileSync(path.join(dir,'private',profile+'.key')).toString('base64');
 profiles[profile]=template.replaceAll('@@PROFILE@@',profile).replaceAll('@@PORT@@',String(port)).replaceAll('@@HOST@@',host).replaceAll('@@ADMIN@@',admin).replaceAll('@@KEY@@',key);
 if(/@@[A-Z]+@@/.test(profiles[profile])) throw Error('Unresolved template');
 fs.writeFileSync(path.join(dir,'private',profile+'-installer.sh'),profiles[profile]);
}
const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
const key=await derive(password,salt,['encrypt']);
const data=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode(JSON.stringify(profiles)));
const b64=x=>Buffer.from(x).toString('base64');
fs.writeFileSync('docs/payload.json',JSON.stringify({version:1,iterations,salt:b64(salt),iv:b64(iv),data:b64(data)}));
console.log('Encrypted both profiles; no plaintext credentials written to public output.');
