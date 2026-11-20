import {test} from 'node:test';
import assert from 'node:assert/strict';
import {derive,unlock,copyAndOpen,iterations} from '../docs/crypto.js';
test('authenticated encryption round trip; wrong password and tampering rejected',async()=>{
 const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
 const key=await derive('test-only',salt,['encrypt']);
 const data=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode('{"city":"test"}'));
 const b64=x=>Buffer.from(x).toString('base64');
 const box={salt:b64(salt),iv:b64(iv),data:b64(data)};
 assert.ok(iterations>=600000); assert.deepEqual(await unlock('test-only',box),{city:'test'});
 await assert.rejects(unlock('wrong',box));
 const corrupt=Buffer.from(data);corrupt[0]^=1;await assert.rejects(unlock('test-only',{...box,data:b64(corrupt)}));
});
test('clipboard success precedes navigation',async()=>{
 const events=[];await copyAndOpen('script',{writeText:async text=>events.push(text)},url=>events.push(url));
 assert.deepEqual(events,['script','http://192.168.80.1/cgi-bin/luci/admin/system/startup']);
});
test('clipboard failure never navigates',async()=>{
 let navigated=false;await assert.rejects(copyAndOpen('script',{writeText:async()=>{throw Error('denied');}},()=>{navigated=true;}));assert.equal(navigated,false);
});
