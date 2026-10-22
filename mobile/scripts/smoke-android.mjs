import {execFileSync} from 'node:child_process';
import {mkdirSync,writeFileSync} from 'node:fs';
const adb=(...args)=>execFileSync('adb',args,{encoding:'utf8',maxBuffer:16*1024*1024}).trim();
const delay=ms=>new Promise(r=>setTimeout(r,ms));
mkdirSync('smoke-evidence',{recursive:true});
adb('install','-r','apk/app-debug.apk');
adb('logcat','-c');
adb('shell','am','start','-W','-n','com.martadha3li.familynews/.MainActivity');
let targets=[];
for(let i=0;i<20;i++){
  await delay(1500);
  const pid=adb('shell','pidof','com.martadha3li.familynews').split(' ')[0];
  if(!pid)continue;
  adb('forward','tcp:9222',`localabstract:webview_devtools_remote_${pid}`);
  try{targets=await (await fetch('http://127.0.0.1:9222/json')).json();if(targets.some(t=>t.webSocketDebuggerUrl))break;}catch{}
}
const target=targets.find(t=>t.webSocketDebuggerUrl);
if(!target)throw new Error('Native WebView did not start');
const inspect=()=>new Promise((resolve,reject)=>{
 const ws=new WebSocket(target.webSocketDebuggerUrl);
 const timer=setTimeout(()=>{ws.close();reject(new Error('WebView evaluation timed out'));},15000);
 ws.onopen=()=>ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression:'JSON.stringify({title:document.title,body:document.body.innerText,login:!!document.querySelector("#auth-form"),native:!!window.Capacitor,origin:location.origin})',returnByValue:true}}));
 ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id!==1)return;clearTimeout(timer);ws.close();if(m.error)reject(new Error(JSON.stringify(m.error)));else resolve(JSON.parse(m.result.result.value));};
 ws.onerror=()=>{clearTimeout(timer);reject(new Error('WebView connection failed'));};
});
let result;for(let i=0;i<30;i++){result=await inspect();if(result.native&&result.login&&result.title==='منصة العوائل'&&result.body.includes('اختر عائلتك'))break;await delay(1000)}
writeFileSync('smoke-evidence/launch.json',JSON.stringify(result,null,2));
writeFileSync('smoke-evidence/logcat.txt',adb('logcat','-d','-t','2000'));
execFileSync('adb',['shell','screencap','-p','/sdcard/launch.png']);
adb('pull','/sdcard/launch.png','smoke-evidence/launch.png');
if(!result.native||!result.login||result.title!=='منصة العوائل'||!result.body.includes('اختر عائلتك'))throw new Error('Family selection screen was not rendered');
async function iconCall(code){return await new Promise((resolve,reject)=>{
 const ws=new WebSocket(target.webSocketDebuggerUrl);const timer=setTimeout(()=>{ws.close();reject(new Error('Icon bridge timed out'))},15000);
 const expression='(async()=>{const m=await import("/capacitor-core.mjs");return JSON.stringify(await m.registerPlugin("FamilyBrand").setFamilyIcon({code:'+JSON.stringify(code)+'}))})()';
 ws.onopen=()=>ws.send(JSON.stringify({id:2,method:'Runtime.evaluate',params:{expression,returnByValue:true,awaitPromise:true}}));
 ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id!==2)return;clearTimeout(timer);ws.close();if(m.error||m.result.exceptionDetails)reject(new Error(JSON.stringify(m.error||m.result.exceptionDetails)));else resolve(JSON.parse(m.result.result.value))};ws.onerror=()=>{clearTimeout(timer);reject(new Error('Icon bridge connection failed'))};
})}
function enabledComponent(name){const dump=adb('shell','dumpsys','package','com.martadha3li.familynews');const block=dump.match(/(?:^|\n)\s*enabledComponents:\s*\n((?:[ \t]+[\w.$]+[ \t]*\n?)+)/)?.[1]||'';return block.includes('.'+name)}
const selected=await iconCall('01');await delay(500);if(selected.icon!=='Family01Launcher'||!enabledComponent('Family01Launcher'))throw new Error('Family launcher icon did not activate');
const reset=await iconCall('');await delay(500);if(reset.icon!=='PlatformLauncher'||!enabledComponent('PlatformLauncher'))throw new Error('Platform launcher icon did not restore');
writeFileSync('smoke-evidence/icon-switch.json',JSON.stringify({selected,reset},null,2));
console.log('PASS: Android first-use family screen, real native family-01 icon activation and platform icon reset.');
