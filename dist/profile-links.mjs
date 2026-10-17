export function openMember(id){document.dispatchEvent(new CustomEvent('family:member',{detail:{id}}));}
export function openNews(id){document.dispatchEvent(new CustomEvent('family:news',{detail:{id:String(id)}}));}
export async function linkedNewsBody(post,table){
 const result=document.createElement('div');result.className='body';const text=String(post.body||''),ids=post.mentioned_member_ids||[];
 if(!ids.length){result.textContent=text;return result;}
 let members=[];try{members=await table('profiles','select=id,display_name&id=in.('+ids.join(',')+')&status=eq.active&limit=20');}catch{}
 const matches=[];for(const member of [...members].sort((a,b)=>b.display_name.length-a.display_name.length)){const token='@'+member.display_name;let start=0;while(start<text.length){const index=text.indexOf(token,start);if(index<0)break;start=index+token.length;const next=text[start];if(next&&/[\p{L}\p{N}]/u.test(next))continue;if(matches.some(x=>index<x.end&&start>x.start))continue;matches.push({start:index,end:start,member});}}
 matches.sort((a,b)=>a.start-b.start);let cursor=0;for(const match of matches){result.append(document.createTextNode(text.slice(cursor,match.start)));const button=document.createElement('button');button.type='button';button.className='mention-link';button.textContent=text.slice(match.start,match.end);button.onclick=()=>openMember(match.member.id);result.append(button);cursor=match.end;}result.append(document.createTextNode(text.slice(cursor)));
 const chips=document.createElement('div');chips.className='post-member-chips';for(const member of members){const button=document.createElement('button');button.type='button';button.className='mention-link';button.textContent='@'+member.display_name;button.onclick=()=>openMember(member.id);chips.append(button);}result.append(chips);return result;
}
