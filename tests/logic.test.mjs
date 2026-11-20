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
test('clipboard and new tab start in gesture, successful copy precedes new-tab navigation',async()=>{
 const events=[];let finish;
 const popup={opener:{},location:{replace:url=>events.push(url)},close:()=>events.push('closed')};
 const task=copyAndOpen('script',{writeText:text=>{events.push(text);return new Promise(resolve=>{finish=resolve})}},(url,target)=>{events.push([url,target]);return popup});
 assert.deepEqual(events,['script',['about:blank','_blank']]);assert.equal(popup.opener,null);
 finish();assert.equal(await task,true);
 assert.deepEqual(events,['script',['about:blank','_blank'],'http://192.168.80.1/cgi-bin/luci/admin/system/startup']);
});
test('clipboard failure closes blank tab and never navigates',async()=>{
 let navigated=false,closed=false;
 const popup={opener:{},location:{replace:()=>{navigated=true}},close:()=>{closed=true}};
 await assert.rejects(copyAndOpen('script',{writeText:async()=>{throw Error('denied');}},()=>popup));
 assert.equal(navigated,false);assert.equal(closed,true);
});
test('blocked popup returns copied status without navigating original tab',async()=>{
 let copied=false;
 assert.equal(await copyAndOpen('script',{writeText:async()=>{copied=true}},()=>null),false);
 assert.equal(copied,true);
});
