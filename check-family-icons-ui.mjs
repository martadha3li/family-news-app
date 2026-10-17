import assert from 'node:assert/strict';
const {JSDOM}=await import(process.env.FAMILY_UI_TEST_MODULE||'jsdom');
const {window}=new JSDOM('<link rel="icon"><link rel="apple-touch-icon"><link rel="manifest">',{url:'https://example.invalid'});globalThis.window=window;globalThis.document=window.document;
const {syncFamilyIcons,familyIconURL}=await import('./dist/family-icons.mjs');
syncFamilyIcons(null);assert.ok(document.querySelector('[rel=icon]').href.endsWith('/icon-512.png'));assert.ok(document.querySelector('[rel=manifest]').href.endsWith('/manifest.webmanifest'));
syncFamilyIcons({id:'one',code:'01',name:'أخبار العائلة'});assert.ok(document.querySelector('[rel=icon]').href.endsWith('/family-01-icon-512.png'));assert.ok(document.querySelector('[rel=apple-touch-icon]').href.endsWith('/family-01-touch-icon.png'));assert.ok(document.querySelector('[rel=manifest]').href.endsWith('/families/01.webmanifest'));
const other={id:'two',code:'02',name:'عائلة أخرى',logo:'data:image/jpeg;base64,YQ=='};syncFamilyIcons(other);assert.equal(familyIconURL(other),other.logo);const manifest=JSON.parse(decodeURIComponent(document.querySelector('[rel=manifest]').href.split(',').slice(1).join(',')));assert.equal(manifest.name,other.name);assert.equal(manifest.icons[0].src,other.logo);assert.equal(manifest.id,'/families/two');
syncFamilyIcons(null);assert.ok(document.querySelector('[rel=manifest]').href.endsWith('/manifest.webmanifest'));
console.log('PASS: platform default, family01 browser/touch/install icons, new-family manifest identity and platform reset.');
