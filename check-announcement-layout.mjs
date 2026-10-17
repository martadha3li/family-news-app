import assert from 'node:assert/strict';
import {announcementLayout} from './dist/announcement-layout.mjs';
for(const width of [280,320,390,768,1200])for(const count of [1,2,3,5,10,50,200]){const result=announcementLayout(width,count);assert.ok(result.cell*count+result.gap*(count-1)<=width-20+.001);assert.ok(result.cell>=0);}
assert.equal(announcementLayout(390,2).mode,'full');assert.equal(announcementLayout(390,4).mode,'compact');assert.equal(announcementLayout(320,5).mode,'icons');
console.log('PASS: every announcement fits across phone/tablet/desktop widths; full titles, compact labels and icons');
