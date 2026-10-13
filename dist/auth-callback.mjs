export function readAuthCallback(hash,now=Math.floor(Date.now()/1000)){
 const values=new URLSearchParams(hash.replace(/^#/,''));
 if(values.has('error'))return {error:values.get('error_code')==='otp_expired'?'انتهت صلاحية رابط الدخول أو استُخدم سابقًا. اطلب رابطًا جديدًا وافتح أحدث رسالة مرة واحدة.':'تعذّر تأكيد الدخول. اطلب رابطًا جديدًا وحاول مجددًا.'};
 const access=values.get('access_token'),refresh=values.get('refresh_token');
 if(!access&&!refresh)return null;
 if(!access||!refresh)return {error:'رابط الدخول غير مكتمل. اطلب رابطًا جديدًا.'};
 const expiry=Number(values.get('expires_in')||3600);
 if(!Number.isFinite(expiry)||expiry<=0)return {error:'انتهت صلاحية جلسة الدخول. اطلب رابطًا جديدًا.'};
 return {recovery:values.get('type')==='recovery',session:{access_token:access,refresh_token:refresh,expires_in:expiry,expires_at:now+expiry,token_type:'bearer'}};
}
