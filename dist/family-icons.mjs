import {Capacitor,registerPlugin} from './capacitor-core.mjs';
const NativeFamilyBrand=registerPlugin('FamilyBrand');
export function familyIconURL(family,size=512){return family?.code==='01'?'/family-01-icon-'+size+'.png':family?.logo||'/icon-'+size+'.png'}
export function syncFamilyIcons(family){
 const name=family?.name||'منصة العوائل';
 const favicon=document.querySelector('link[rel=icon]');if(favicon){favicon.href=familyIconURL(family);favicon.type=family?.logo&&family?.code!=='01'?'image/jpeg':'image/png'}
 const touch=document.querySelector('link[rel=apple-touch-icon]');if(touch)touch.href=family?.code==='01'?'/family-01-touch-icon.png':family?.logo||'/apple-touch-icon.png';
 const manifest=document.querySelector('link[rel=manifest]');if(manifest){if(family?.code==='01')manifest.href='/families/01.webmanifest';else if(!family)manifest.href='/manifest.webmanifest';else{const data={id:'/families/'+family.id,name,short_name:name,lang:'ar',dir:'rtl',start_url:'/',scope:'/',display:'standalone',background_color:'#f6f9fc',theme_color:'#123F50',icons:[{src:familyIconURL(family),sizes:'512x512',type:family.logo?'image/jpeg':'image/png',purpose:'any'}]};manifest.href='data:application/manifest+json,'+encodeURIComponent(JSON.stringify(data));}}
 if(Capacitor.getPlatform()==='android')NativeFamilyBrand.setFamilyIcon({code:family?.code||''}).catch(()=>{});
}
