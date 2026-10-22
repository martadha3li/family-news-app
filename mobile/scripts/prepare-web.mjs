import { cp,readFile,writeFile,rm,mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const source=path.join(root,'../dist'),dest=path.join(root,'www');
await rm(dest,{recursive:true,force:true});
await mkdir(dest,{recursive:true});
await cp(source,dest,{recursive:true,filter:src=>!['server','.openai'].includes(path.basename(src))});
for(const name of ['app.js','community.mjs','social.mjs']){
 let js=await readFile(path.join(dest,name),'utf8');
 js=js.replaceAll("encodeURIComponent(location.origin+'/')","encodeURIComponent('https://family-news-app.nimbletide.chatgpt.site/')");
 js=js.replace("if('serviceWorker'in navigator)navigator.serviceWorker.register('/sw.js').catch(()=>{});",'');
 await writeFile(path.join(dest,name),js);
}
let html=await readFile(path.join(dest,'index.html'),'utf8');
html=html.replace('<link rel="manifest" href="/manifest.webmanifest">','');
html=html.replace(/<details><summary>إضافة التطبيق إلى الشاشة الرئيسية<\/summary>[\s\S]*?<\/details>/,'');
await writeFile(path.join(dest,'index.html'),html);
await writeFile(path.join(dest,'style.css'),(await readFile(path.join(dest,'style.css'),'utf8'))+'\nbody{padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)}\n');
console.log('Prepared bundled native web assets.');
