import {execFileSync} from 'node:child_process';
import {mkdirSync,writeFileSync} from 'node:fs';
const adb=(...args)=>execFileSync('adb',args,{encoding:'utf8'}).trim();
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
const result=await new Promise((resolve,reject)=>{
 const ws=new WebSocket(target.webSocketDebuggerUrl);
 const timer=setTimeout(()=>{ws.close();reject(new Error('WebView evaluation timed out'));},15000);
 ws.onopen=()=>ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression:'JSON.stringify({title:document.title,body:document.body.innerText,login:!!document.querySelector("#auth-form"),native:!!window.Capacitor,origin:location.origin})',returnByValue:true}}));
 ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id!==1)return;clearTimeout(timer);ws.close();if(m.error)reject(new Error(JSON.stringify(m.error)));else resolve(JSON.parse(m.result.result.value));};
 ws.onerror=()=>{clearTimeout(timer);reject(new Error('WebView connection failed'));};
});
writeFileSync('smoke-evidence/launch.json',JSON.stringify(result,null,2));
writeFileSync('smoke-evidence/logcat.txt',adb('logcat','-d'));
execFileSync('adb',['shell','screencap','-p','/sdcard/launch.png']);
adb('pull','/sdcard/launch.png','smoke-evidence/launch.png');
if(!result.native||!result.login||!result.body.includes('أخبار العائلة'))throw new Error('Bundled login screen was not rendered');
console.log('PASS: native Android package launches and renders the Arabic login screen.');
