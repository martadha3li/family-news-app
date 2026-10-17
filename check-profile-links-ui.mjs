import assert from 'node:assert/strict';
const {JSDOM}=await import(process.env.FAMILY_UI_TEST_MODULE||'jsdom');
const {window}=new JSDOM('<body></body>',{url:'https://example.invalid'});globalThis.document=window.document;globalThis.CustomEvent=window.CustomEvent;
const {linkedNewsBody,openNews}=await import('./dist/profile-links.mjs');
const id='00000000-0000-4000-8000-000000000001';let member,news;document.addEventListener('family:member',e=>member=e.detail.id);document.addEventListener('family:news',e=>news=e.detail.id);
const body=await linkedNewsBody({body:'مرحبا @أحمد علي ثم @أحمد علي <img src=x onerror=alert(1)>',mentioned_member_ids:[id]},async()=>[{id,display_name:'أحمد علي'}]);
assert.equal(body.querySelectorAll('button').length,3);assert.equal(body.querySelector('img'),null);assert.ok(body.textContent.includes('<img'));body.querySelector('button').click();assert.equal(member,id);openNews(123);assert.equal(news,'123');
const plain=await linkedNewsBody({body:'@أحمد عليان',mentioned_member_ids:[id]},async()=>[{id,display_name:'أحمد علي'}]);assert.equal(plain.querySelectorAll('button').length,1);
console.log('PASS: repeated saved mentions and member chips open the correct profile, news IDs link, HTML stays text, no name-prefix false match');
