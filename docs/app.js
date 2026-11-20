import {unlock,copyAndOpen} from './crypto.js';
const $ = id => document.getElementById(id);
let profiles;
$('unlock').addEventListener('submit', async event => {
  event.preventDefault(); $('enter').disabled=true; $('message').textContent='Открываем…';
  try {
    const response=await fetch('./payload.json',{cache:'no-store'});
    if(!response.ok) throw Error();
    profiles=await unlock($('password').value,await response.json());
    $('password').value=''; $('unlock').hidden=true; $('steps').hidden=false; $('message').textContent='';
  } catch { $('message').textContent='Не получилось открыть. Проверьте пароль и интернет.'; }
  finally { $('enter').disabled=false; }
});
$('profile').addEventListener('change',()=>{ $('copy').disabled=!$('profile').value; $('fallback').hidden=true; });
$('copy').addEventListener('click', async()=>{
  const text=profiles[$('profile').value];
  if(!text) return;
  try { await copyAndOpen(text,navigator.clipboard,url=>location.assign(url)); }
  catch { $('manual').value=text; $('fallback').hidden=false; $('message').textContent='Safari не разрешил копирование. Нажмите на текст, выберите всё и скопируйте. Затем откройте роутер.'; }
});
$('manual').addEventListener('click',()=>{ $('manual').focus(); $('manual').select(); $('manual').setSelectionRange(0,$('manual').value.length); });
