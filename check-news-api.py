"""Live regression: tests only newly created disposable news, then removes it."""
import getpass,json,urllib.request,urllib.parse,uuid
from pathlib import Path
BASE='https://dlkykiducjimwehfhxfq.supabase.co'
KEY='sb_publishable_em1zUQS1tUhfk_8Ji17n8g_H8CPQynt'
password=getpass.getpass('Account password for API verification: ')
session=None
def request(path,method='GET',data=None,content_type='application/json'):
 headers={'apikey':KEY,'Content-Type':content_type,'Prefer':'return=representation'}
 if session:headers['Authorization']='Bearer '+session['access_token']
 req=urllib.request.Request(BASE+path,data=None if data is None else data if isinstance(data,bytes) else json.dumps(data).encode(),headers=headers,method=method)
 with urllib.request.urlopen(req,timeout=25) as response:
  body=response.read()
  return json.loads(body) if body else None
session=request('/auth/v1/token?grant_type=password','POST',{'email':'martadha3li@gmail.com','password':password})
uid=session['user']['id']
post_id=None
image_path=uid+'/test-'+uuid.uuid4().hex+'.png'
image_uploaded=False
try:
 request('/storage/v1/object/news-images/'+image_path,'POST',Path(__file__).with_name('dist').joinpath('icon-192.png').read_bytes(),'image/png')
 image_uploaded=True
 rows=request('/rest/v1/posts','POST',{'author_id':uid,'title':'اختبار تقني مؤقت '+uuid.uuid4().hex[:8],'body':'سجل اختبار مؤقت يُزال تلقائيًا بعد التحقق.','published':True,'image_path':image_path})
 post_id=rows[0]['id']
 request('/rest/v1/comments','POST',{'post_id':post_id,'author_id':uid,'body':'تعليق اختبار مؤقت'})
 request('/rest/v1/likes','POST',{'post_id':post_id,'user_id':uid})
 select='id,profiles:profiles!posts_author_id_fkey(display_name),comments(count),likes(count)'
 rows=request('/rest/v1/posts?'+urllib.parse.urlencode({'select':select,'id':'eq.'+str(post_id)}))
 assert rows[0]['comments'][0]['count']==1 and rows[0]['likes'][0]['count']==1
 signed=request('/storage/v1/object/sign/news-images/'+image_path,'POST',{'expiresIn':60})
 with urllib.request.urlopen(BASE+'/storage/v1'+signed['signedURL'],timeout=25) as response:assert response.status==200 and len(response.read())>0
 ads=request('/rest/v1/announcements?select=id,title,starts_at,ends_at,enabled&limit=20')
 print('PASS: news, private image upload/read, author embedding, comments, likes, announcement API')
finally:
 if post_id is not None:
  removed=request('/rest/v1/posts?id=eq.'+str(post_id),'DELETE')
  assert removed and removed[0]['id']==post_id
  assert request('/rest/v1/posts?select=id&id=eq.'+str(post_id))==[]
  assert request('/rest/v1/comments?select=id&post_id=eq.'+str(post_id))==[]
  assert request('/rest/v1/likes?select=post_id&post_id=eq.'+str(post_id))==[]
  print('PASS: permanent deletion and cascade cleanup of disposable fixture')
 if image_uploaded:request('/storage/v1/object/news-images','DELETE',{'prefixes':[image_path]})
 request('/auth/v1/logout?scope=local','POST',{})
