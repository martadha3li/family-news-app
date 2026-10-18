const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const headers={apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'};
async function rpc(action:string,data:Record<string,unknown>={}){const r=await fetch(url+'/rest/v1/rpc/lifecycle_backend',{method:'POST',headers,body:JSON.stringify({action,data})});if(!r.ok)throw Error('Lifecycle operation failed: '+r.status);return r.json()}
Deno.serve(async(req)=>{if(req.method!=='POST')return new Response('',{status:405});try{
 if(!await rpc('verify',{stamp:req.headers.get('x-family-time'),signature:req.headers.get('x-family-signature')}))return new Response('',{status:401});
 const work=await rpc('tick');let sent=0,removed=0;
 for(const mail of work.mail){const token=Deno.env.get('RESEND_API_KEY'),from=Deno.env.get('LIFECYCLE_MAIL_FROM');if(!token||!from){await rpc('mail_error',{id:mail.id,error:'Email provider not configured; paid deletion countdown has not started'});continue}
 try{const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json','Idempotency-Key':'family-lifecycle-'+mail.id},body:JSON.stringify({from,to:[mail.recipient],subject:mail.subject,text:mail.body})});if(!r.ok)throw Error('Email provider rejected delivery: '+r.status);const result=await r.json();if(!result.id)throw Error('Missing message receipt');await rpc('mail_sent',{id:mail.id,provider_id:result.id});sent++}catch(e){await rpc('mail_error',{id:mail.id,error:String(e)})}}
 for(const job of work.jobs){try{
 if(job.phase==='files'){const files=await rpc('files',{tenant:job.tenant_id});if(files.length){for(const bucket of [...new Set(files.map((f:{bucket_id:string})=>f.bucket_id))]){const r=await fetch(url+'/storage/v1/object/'+encodeURIComponent(String(bucket)),{method:'DELETE',headers,body:JSON.stringify({prefixes:files.filter((f:{bucket_id:string})=>f.bucket_id===bucket).map((f:{name:string})=>f.name)})});if(!r.ok)throw Error('Storage removal failed: '+r.status)}continue}await rpc('purge_data',{tenant:job.tenant_id})}
 for(const id of job.members){const r=await fetch(url+'/auth/v1/admin/users/'+encodeURIComponent(id),{method:'DELETE',headers});if(!r.ok&&r.status!==404)throw Error('Auth removal failed: '+r.status)}
 await rpc('finish',{tenant:job.tenant_id});removed++
 }catch(e){await rpc('error',{tenant:job.tenant_id,error:String(e)})}}
 return Response.json({ok:true,sent,removed,mail_configured:!!Deno.env.get('RESEND_API_KEY')&&!!Deno.env.get('LIFECYCLE_MAIL_FROM')});
 }catch{return Response.json({ok:false},{status:500})}});
