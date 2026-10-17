export function initPromotions({state,req,table,element,button,toast,origin}){
 let checked='',generation=0,dialog=null,timer=null,editPath='';
 const field=element('fieldset');field.id='promo-settings';field.append(element('legend','إعلان دعائي بعد الدخول'));
 function input(id,label,type,value){const l=element('label',label),i=element('input');i.id=id;i.type=type;i.value=value;l.append(i);field.append(l);return i}
 const enabled=input('promo-enabled','صورة على كامل الشاشة','checkbox','');
 const file=input('promo-image','صورة الإعلان (حتى 20 ميجابايت)','file','');file.accept='image/*';
 const seconds=input('promo-seconds','مدة العرض بالثواني (1–300)','number','8');seconds.min=1;seconds.max=300;
 const days=input('promo-days','يتكرر كل عدد أيام (1 يوم، 2 يوم أو أكثر)','number','1');days.min=1;days.max=3650;
 const note=element('small','الصورة كاملة دون قص. يمكن الإغلاق فورًا أو عدم إظهار الإعلان مجددًا.');field.append(note);document.getElementById('ad-body').closest('label').after(field);
 function sync(){for(const i of[file,seconds,days])i.disabled=!enabled.checked}
 enabled.onchange=sync;sync();
 function reset(ad={}){editPath=ad.image_path||'';enabled.checked=!!ad.is_popup;file.value='';seconds.value=ad.display_seconds||8;days.value=ad.repeat_days||1;note.textContent=editPath?'صورة محفوظة. اختر ملفًا لاستبدالها.':'اختر الصورة. يستطيع العضو إغلاق الإعلان فورًا أو عدم إظهاره مجددًا.';sync()}
 async function compressed(file){if(file.size>20*1024*1024)throw Error('اختر صورة أقل من 20 ميجابايت.');const img=new Image(),url=URL.createObjectURL(file);try{img.src=url;await img.decode();for(let attempt=0;attempt<7;attempt++){const scale=Math.min(1,1600/Math.max(img.naturalWidth,img.naturalHeight))*Math.pow(.8,attempt),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.naturalWidth*scale));canvas.height=Math.max(1,Math.round(img.naturalHeight*scale));const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(img,0,0,canvas.width,canvas.height);const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',.78-attempt*.05));if(blob&&blob.size<=409600)return blob}throw Error('تعذّر ضغط الصورة.')}finally{URL.revokeObjectURL(url)}}
 async function prepare(){const is_popup=enabled.checked,display_seconds=Number(seconds.value),repeat_days=Number(days.value);if(!Number.isInteger(display_seconds)||display_seconds<1||display_seconds>300||!Number.isInteger(repeat_days)||repeat_days<1||repeat_days>3650)throw Error('تحقق من الثواني وعدد أيام التكرار.');let image_path=editPath||null,uploaded=null;if(is_popup&&file.files[0]){const blob=await compressed(file.files[0]);uploaded=state.user.id+'/'+crypto.randomUUID()+'.jpg';await req('/storage/v1/object/ad-images/'+uploaded,{method:'POST',body:blob,raw:true,headers:{'Content-Type':'image/jpeg'}});image_path=uploaded}if(is_popup&&!image_path)throw Error('اختر صورة الإعلان الدعائي.');return {values:{is_popup,image_path,display_seconds,repeat_days},uploaded}}
 async function rollback(path){if(path)await req('/storage/v1/object/ad-images',{method:'DELETE',body:{prefixes:[path]}}).catch(()=>{})}
 function clear(){generation++;checked='';clearInterval(timer);timer=null;if(dialog){dialog.close();dialog.remove();dialog=null}}
 async function show(){if(!state.user||state.profile?.status!=='active'||checked===state.user.id)return;checked=state.user.id;const owner=checked,version=generation;
  const ads=await req('/rest/v1/rpc/promo_due',{method:'POST',body:{}});
  for(const ad of ads){if(version!==generation||state.user?.id!==owner)return;const key='promo-hidden-'+owner+'-'+ad.id;
   if(localStorage.getItem(key)==='true'){await req('/rest/v1/rpc/promo_hide',{method:'POST',body:{ad_id:ad.id,hide:true}}).catch(()=>{});continue}
   let img;try{const signed=await req('/storage/v1/object/sign/ad-images/'+ad.image_path.split('/').map(encodeURIComponent).join('/'),{method:'POST',body:{expiresIn:600}});img=element('img');img.alt=ad.title;img.src=origin+'/storage/v1'+signed.signedURL;let timeout;try{await Promise.race([img.decode(),new Promise((_,reject)=>{timeout=setTimeout(()=>reject(Error('image timeout')),15000)})]);}finally{clearTimeout(timeout)}}catch{continue}
   if(version!==generation||state.user?.id!==owner)return;
   const claimed=await req('/rest/v1/rpc/promo_claim',{method:'POST',body:{ad_id:ad.id}});if(!claimed)continue;if(version!==generation||state.user?.id!==owner)return;
   const d=element('dialog',undefined,'promo-fullscreen');dialog=d;const header=element('div',undefined,'promo-header'),count=element('span'),close=button('×',()=>finish(),'promo-close');close.setAttribute('aria-label','إغلاق الإعلان فورًا');header.append(count,close);const footer=element('label',undefined,'promo-footer'),hide=element('input');hide.type='checkbox';hide.id='promo-opt-out';footer.append(hide,document.createTextNode('عدم إظهار هذا الإعلان مرة أخرى'));
   hide.onchange=()=>{try{localStorage.setItem(key,String(hide.checked))}catch{}req('/rest/v1/rpc/promo_hide',{method:'POST',body:{ad_id:ad.id,hide:hide.checked}}).catch(()=>toast('حُفظ التفضيل على جهازك وتعذّرت مزامنته الآن.'))};
   function finish(){clearInterval(timer);timer=null;d.close();d.remove();if(dialog===d)dialog=null}
   d.addEventListener('cancel',e=>{e.preventDefault();finish()});d.append(img,header,footer);document.body.append(d);d.showModal();let remaining=ad.display_seconds*1000,last=Date.now();count.textContent='إعلان دعائي · '+ad.display_seconds+' ث';timer=setInterval(()=>{const now=Date.now();if(!document.hidden)remaining-=now-last;last=now;count.textContent='إعلان دعائي · '+Math.max(0,Math.ceil(remaining/1000))+' ث';if(remaining<=0)finish()},250);return d;
  }
 }
 return {reset,prepare,rollback,show,clear};
}
