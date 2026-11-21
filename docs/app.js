import {unlock,copyAndOpen,routerUrlForProfile} from './crypto.js?v=6';
const $ = id => document.getElementById(id);
let profiles;
const selectedProfile=()=>document.querySelector('input[name="profile"]:checked')?.value;
$('unlock').addEventListener('submit', async event => {
  event.preventDefault(); $('enter').disabled=true; $('message').textContent='Открываем…';
  try {
    const response=await fetch('./payload.json?v=6',{cache:'no-store'});
    if(!response.ok) throw Error();
    profiles=await unlock($('password').value,await response.json());
    $('password').value=''; $('unlock').hidden=true; $('steps').hidden=false; $('message').textContent='';
  } catch { $('message').textContent='Не получилось открыть. Проверьте пароль и интернет.'; }
  finally { $('enter').disabled=false; }
});
$('profile').addEventListener('change',()=>{ $('copy').disabled=!selectedProfile(); $('fallback').hidden=true; $('addressHelp').hidden=selectedProfile()!=='home'; if(selectedProfile()) $('routerLink').href=routerUrlForProfile(selectedProfile()); });
$('copy').addEventListener('click', async()=>{
  const text=profiles[selectedProfile()];
  if(!text) return;
  $('fallback').hidden=true;
  try {
    const opened=await copyAndOpen(text,navigator.clipboard,(...args)=>window.open(...args),routerUrlForProfile(selectedProfile()));
    if(!opened) { $('manualCopy').hidden=true; $('fallback').hidden=false; $('message').textContent='Текст скопирован. Нажмите «Открыть роутер» ниже.'; }
    else $('message').textContent='Текст скопирован. Роутер открыт в новой вкладке.';
  }
  catch { $('manual').value=text; $('manualCopy').hidden=false; $('fallback').hidden=false; $('message').textContent='Не удалось скопировать. Нажмите на текст, выберите всё и скопируйте. Затем откройте роутер.'; }
});
$('manual').addEventListener('click',()=>{ $('manual').focus(); $('manual').select(); $('manual').setSelectionRange(0,$('manual').value.length); });
