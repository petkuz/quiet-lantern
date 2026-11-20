export const iterations = 900000;
export async function derive(password, salt, usage) {
  const material = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey({name:'PBKDF2',hash:'SHA-256',salt,iterations},material,{name:'AES-GCM',length:256},false,usage);
}
export async function unlock(password, box) {
  const bytes = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
  const key = await derive(password, bytes(box.salt), ['decrypt']);
  return JSON.parse(new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes(box.iv)},key,bytes(box.data))));
}
export const routerUrl='http://192.168.80.1/cgi-bin/luci/admin/system/startup';
export async function copyAndOpen(text, clipboard, openWindow) {
  // Both calls happen synchronously during the tap, before the first await.
  const copying=clipboard.writeText(text);
  let popup;
  try { popup=openWindow('about:blank','_blank'); } catch { popup=null; }
  if(popup) popup.opener=null;
  try { await copying; }
  catch(error) { if(popup) popup.close(); throw error; }
  if(!popup) return false;
  popup.location.replace(routerUrl);
  return true;
}
