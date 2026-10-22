import {Capacitor,registerPlugin} from './capacitor-core.mjs';
export const NativeFamilyBrand=registerPlugin('FamilyBrand');
export function familyIconURL(family,size=512){return family?.code==='01'?'/family-01-icon-'+size+'.png':family?.logo||'/icon-'+size+'.png'}
export function syncFamilyIcons(family){
 const name=family?.name||'منصة العوائل';
 const favicon=document.querySelector('link[rel=icon]');if(favicon){favicon.href=familyIconURL(family);favicon.type=family?.logo&&family?.code!=='01'?'image/jpeg':'image/png'}
 const touch=document.querySelector('link[rel=apple-touch-icon]');if(touch)touch.href=family?.code?'https://family-news-app.nimbletide.chatgpt.site/family/'+encodeURIComponent(family.code)+'/icon':'/apple-touch-icon.png';
 const manifest=document.querySelector('link[rel=manifest]');if(manifest)manifest.href=family?.code?'https://family-news-app.nimbletide.chatgpt.site/family/'+encodeURIComponent(family.code)+'/manifest.webmanifest':'/manifest.webmanifest';
 let title=document.querySelector('meta[name=apple-mobile-web-app-title]');if(!title){title=document.createElement('meta');title.name='apple-mobile-web-app-title';document.head.append(title)}title.content=name;
 if(Capacitor.getPlatform()==='android')NativeFamilyBrand.setFamilyIcon({code:family?.code||''}).catch(()=>{});
}
