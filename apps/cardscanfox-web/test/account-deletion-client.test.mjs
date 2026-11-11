import assert from 'node:assert/strict';
import test from 'node:test';
import {buildDeletionRequest,initAccountDeletion,normalizeDeletionEmail,normalizeDeletionPlatform} from '../public/assets/account-deletion.js';

class FakeElement {
 constructor({value='',checked=false,hidden=false,disabled=false}={}){this.value=value;this.checked=checked;this.hidden=hidden;this.disabled=disabled;this.textContent='';this.attributes=new Map();this.listeners=new Map();this.selected=false;this.fieldset=null;}
 setAttribute(name,value){this.attributes.set(name,String(value));}
 getAttribute(name){return this.attributes.get(name)??null;}
 addEventListener(name,listener){const list=this.listeners.get(name)??[];list.push(listener);this.listeners.set(name,list);}
 dispatch(name,values={}){const event={key:values.key,prevented:false,preventDefault(){this.prevented=true;}};for(const listener of this.listeners.get(name)??[])listener(event);return event;}
 closest(selector){return selector==='fieldset'?this.fieldset:null;}
 select(){this.selected=true;}
}

function page({clipboard,openMailto}={}){
 const android=new FakeElement(),ios=new FakeElement(),fieldset=new FakeElement();android.value='android';ios.value='ios';android.fieldset=fieldset;ios.fieldset=fieldset;
 const email=new FakeElement(),open=new FakeElement({disabled:true}),copy=new FakeElement({disabled:true});
 const platformError=new FakeElement({hidden:true}),emailError=new FakeElement({hidden:true}),scopeTitle=new FakeElement(),scopeNotice=new FakeElement(),iosSubscription=new FakeElement({hidden:true}),details=new FakeElement({hidden:true}),detailsTitle=new FakeElement(),template=new FakeElement(),status=new FakeElement();
 const map=new Map([
  ['[data-deletion-email]',email],['[data-open-deletion-email]',open],['[data-copy-deletion-request]',copy],
  ['[data-deletion-platform-error]',platformError],['[data-deletion-email-error]',emailError],['[data-deletion-scope-title]',scopeTitle],
  ['[data-deletion-scope-notice]',scopeNotice],['[data-ios-subscription]',iosSubscription],['[data-deletion-details]',details],
  ['[data-deletion-details-title]',detailsTitle],['[data-deletion-template]',template],['[data-deletion-status]',status],
 ]);
 const root={querySelector:selector=>map.get(selector)??null,querySelectorAll:selector=>selector==='input[data-deletion-platform]'?[android,ios]:[]};
 const opened=[];const controller=initAccountDeletion(root,{clipboard,openMailto:openMailto??(href=>opened.push(href))});
 const selectPlatform=platform=>{android.checked=platform==='android';ios.checked=platform==='ios';(platform==='android'?android:ios).dispatch('change');};
 return {android,ios,fieldset,email,open,copy,platformError,emailError,scopeTitle,scopeNotice,iosSubscription,details,detailsTitle,template,status,opened,controller,selectPlatform};
}

const flush=()=>new Promise(resolve=>setImmediate(resolve));
function deferred(){let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};}

test('request construction keeps platform scope and safely encodes aliases and Unicode',()=>{
 const android=buildDeletionRequest('android','collector+deck@example.com');
 assert.equal(android.subject,'Card AI account deletion request — Android');
 assert.match(decodeURIComponent(android.mailto),/^mailto:support@tcgcard\.fun\?subject=Card AI account deletion request — Android&body=/);
 assert.match(android.plainText,/Platform: Android/);assert.match(android.plainText,/iOS account and its data are not part/);assert.match(android.plainText,/verify my identity/);
 const ios=buildDeletionRequest('IOS','测试者@example.com');
 assert.match(ios.mailto,/%E6%B5%8B%E8%AF%95%E8%80%85%40example\.com/);assert.match(ios.plainText,/Platform: iOS/);assert.match(ios.plainText,/Android account and its data are not part/);
});

test('invalid platforms, addresses and control characters fail explicitly',()=>{
 assert.equal(normalizeDeletionPlatform('windows'),null);assert.equal(normalizeDeletionPlatform('ios\nBcc:x'),null);
 for(const value of ['', 'missing-at.example.com','a@b','a@b.com\r\nBcc:x@example.com'])assert.equal(normalizeDeletionEmail(value),null,value);
 assert.throws(()=>buildDeletionRequest('google','a@example.com'),/Android or iOS/);
 assert.throws(()=>buildDeletionRequest('ios','bad'),/valid account email/);
});

test('initial state has no selected platform and invalid input retains the entered email',()=>{
 const view=page();assert.equal(view.android.checked,false);assert.equal(view.ios.checked,false);assert.equal(view.open.disabled,false);assert.equal(view.copy.disabled,false);
 view.email.value='not-an-email';view.open.dispatch('click');
 assert.equal(view.email.value,'not-an-email');assert.equal(view.platformError.hidden,false);assert.equal(view.emailError.hidden,false);assert.equal(view.fieldset.getAttribute('aria-invalid'),'true');assert.equal(view.email.getAttribute('aria-invalid'),'true');assert.equal(view.details.hidden,true);
});

test('click and Enter prepare the same draft and only hand it to the mail client',()=>{
 const view=page();view.selectPlatform('android');view.email.value='collector@example.com';view.open.dispatch('click');
 assert.equal(view.opened.length,1);assert.match(view.opened[0],/^mailto:support@tcgcard\.fun/);assert.equal(view.details.hidden,false);assert.match(view.status.textContent,/not been received until you send/);assert.doesNotMatch(view.status.textContent,/submitted|deleted/i);
 view.email.dispatch('input');view.email.value='second@example.com';const event=view.email.dispatch('keydown',{key:'Enter'});
 assert.equal(event.prevented,true);assert.equal(view.opened.length,2);assert.match(decodeURIComponent(view.opened[1]),/second@example.com/);
});

test('mail client failure keeps a manual request without claiming submission',()=>{
 const view=page({openMailto(){throw new Error('unavailable');}});view.selectPlatform('android');view.email.value='collector@example.com';view.open.dispatch('click');
 assert.equal(view.details.hidden,false);assert.match(view.status.textContent,/could not be opened/);assert.match(view.status.textContent,/Nothing has been sent/);assert.match(view.template.value,/support@tcgcard\.fun/);
});

test('copy reports success only after the clipboard accepts the exact request',async()=>{
 const writes=[];const view=page({clipboard:{async writeText(value){writes.push(value);}}});view.selectPlatform('ios');view.email.value='collector@example.com';view.copy.dispatch('click');await flush();
 assert.equal(writes.length,1);assert.equal(writes[0],view.template.value);assert.match(view.status.textContent,/copied/);assert.match(view.status.textContent,/Nothing has been sent/);
});

test('missing or rejected clipboard leaves selectable manual details',async()=>{
 for(const clipboard of [null,{async writeText(){throw new Error('denied');}}]){
  const view=page({clipboard});view.selectPlatform('android');view.email.value='collector@example.com';view.copy.dispatch('click');await flush();
  assert.equal(view.template.selected,true);assert.match(view.status.textContent,/copy them manually/i);assert.doesNotMatch(view.status.textContent,/details copied/i);
 }
});

test('editing input clears old output and ignores a late clipboard result',async()=>{
 const pending=deferred();const view=page({clipboard:{writeText(){return pending.promise;}}});view.selectPlatform('android');view.email.value='first@example.com';view.copy.dispatch('click');
 assert.equal(view.details.hidden,false);view.email.value='second@example.com';view.email.dispatch('input');assert.equal(view.details.hidden,true);assert.equal(view.template.value,'');assert.equal(view.status.textContent,'');
 pending.resolve();await flush();assert.equal(view.details.hidden,true);assert.equal(view.status.textContent,'');
});

test('platform changes replace the scope, clear stale drafts and show the iOS subscription boundary only for iOS',()=>{
 const view=page();view.selectPlatform('android');view.email.value='collector@example.com';view.open.dispatch('click');assert.match(view.scopeNotice.textContent,/iOS account/);assert.equal(view.iosSubscription.hidden,true);
 view.selectPlatform('ios');assert.equal(view.details.hidden,true);assert.equal(view.template.value,'');assert.match(view.scopeTitle.textContent,/iOS platform/);assert.match(view.scopeNotice.textContent,/Android account/);assert.equal(view.iosSubscription.hidden,false);
 view.selectPlatform('android');assert.equal(view.iosSubscription.hidden,true);
});
