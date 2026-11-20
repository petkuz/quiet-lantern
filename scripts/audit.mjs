import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {unlock} from '../docs/crypto.js';
const dir=path.join(process.env.LOCALAPPDATA,'quiet-lantern');
const password=fs.readFileSync(path.join(dir,'page-password'),'utf8').trim();
const box=JSON.parse(fs.readFileSync('docs/payload.json','utf8'));
const profiles=await unlock(password,box);
for(const profile of ['city','dacha']) {
 if(profiles[profile]!==fs.readFileSync(path.join(dir,'private',profile+'-installer.sh'),'utf8') || /@@[A-Z]+@@/.test(profiles[profile])) throw Error('Payload mismatch');
}
const files=execFileSync('git',['ls-files','-z'],{encoding:'utf8'}).split('\0').filter(Boolean);
const secretStrings=[password,...['city','dacha'].map(p=>fs.readFileSync(path.join(dir,'private',p+'.key')).toString('base64'))];
const history=execFileSync('git',['log','--all','-p','--no-ext-diff'],{encoding:'utf8',maxBuffer:4*1024*1024});
for(const text of [...files.filter(f=>!f.endsWith('.png')).map(f=>fs.readFileSync(f,'utf8')),history]) {
 if(secretStrings.some(secret=>text.includes(secret)) || /BEGIN (OPENSSH|RSA|EC) PRIVATE KEY/.test(text)) throw Error('Private material detected; stop publication');
}
console.log('Payload matches private generated installers; no unresolved markers or plaintext credentials in tracked files/history.');
