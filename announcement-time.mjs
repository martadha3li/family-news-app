export function announcementState(ad,now=Date.now()){
 if(!ad.enabled)return 'disabled';
 if(now>=Date.parse(ad.ends_at))return 'expired';
 if(now<Date.parse(ad.starts_at))return 'scheduled';
 return 'active';
}
export function localInputValue(date){
 const d=new Date(date);
 return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16);
}
export function announcementPeriod(start,end){
 const s=new Date(start),e=new Date(end);
 if(!Number.isFinite(s.getTime())||!Number.isFinite(e.getTime())||e<=s)throw new Error('اختر تاريخ نهاية يأتي بعد تاريخ البداية.');
 return {starts_at:s.toISOString(),ends_at:e.toISOString()};
}
