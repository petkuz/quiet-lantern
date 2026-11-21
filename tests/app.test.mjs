import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {routerUrlForProfile} from '../docs/crypto.js';

const source=fs.readFileSync('docs/app.js','utf8');
test('HTML, module imports and ciphertext fetch share a cache-busting release',()=>{
 const html=fs.readFileSync('docs/index.html','utf8');
 const urls=[html.match(/href="(style\.css[^\"]+)"/)[1],html.match(/src="(app\.js[^\"]+)"/)[1],source.match(/from '([^']+)'/)[1],source.match(/fetch\('([^']+)'/)[1]];
 assert.deepEqual(urls.map(url=>new URL(url,'https://example.test/').searchParams.get('v')),['5','5','5','5']);
 assert.deepEqual([...html.matchAll(/name="profile" value="([^"]+)"/g)].map(x=>x[1]),['city','dacha','home']);
});

function fixture(copy) {
 const nodes={};
 for(const id of ['unlock','enter','message','password','steps','profile','copy','fallback','manualCopy','manual','routerLink']) nodes[id]={hidden:true,disabled:id==='copy',value:'',handlers:{},addEventListener(event,handler){this.handlers[event]=handler;}};
 let selected;
 const document={getElementById:id=>nodes[id],querySelector:()=>selected};
 new Function('document','unlock','copyAndOpen','fetch','window','navigator','routerUrlForProfile',source.replace(/^import .*;\n/,''))(document,async()=>({city:'city-text',dacha:'dacha-text',home:'home-text'}),copy,async()=>({ok:true,json:async()=>({})}),{open(){}},{clipboard:{}},routerUrlForProfile);
 return {nodes,select(value){selected={value};nodes.profile.handlers.change();},async unlock(){await nodes.unlock.handlers.submit({preventDefault(){}});}};
}

test('radio selection enables copy; blocked popup exposes only the router link',async()=>{
 let copied;
 const page=fixture(async text=>{copied=text;return false;});
 await page.unlock();
 assert.equal(page.nodes.copy.disabled,true);
 page.select('city');assert.equal(page.nodes.copy.disabled,false);
 await page.nodes.copy.handlers.click();
 assert.equal(copied,'city-text');assert.equal(page.nodes.fallback.hidden,false);assert.equal(page.nodes.manualCopy.hidden,true);
});

test('all three selections copy their own script and target the correct fallback/new tab URL',async()=>{
 for(const profile of ['city','dacha','home']) {
  let copied,target;
  const page=fixture(async(text,clipboard,open,url)=>{copied=text;target=url;return false});
  await page.unlock();page.select(profile);await page.nodes.copy.handlers.click();
  assert.equal(copied,profile+'-text');assert.equal(target,routerUrlForProfile(profile));assert.equal(page.nodes.routerLink.href,target);
 }
});

test('copy denial reveals selected profile text for manual copying',async()=>{
 const page=fixture(async()=>{throw Error('denied');});
 await page.unlock();page.select('dacha');await page.nodes.copy.handlers.click();
 assert.equal(page.nodes.manual.value,'dacha-text');assert.equal(page.nodes.fallback.hidden,false);assert.equal(page.nodes.manualCopy.hidden,false);
});
