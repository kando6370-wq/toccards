import {detectCardCentering, measureFromQuads} from './card-centering.js';

const NS='http://www.w3.org/2000/svg';
const corners=['top left','top right','bottom right','bottom left'];
const copy=quad=>quad.map(point=>({...point}));
function element(tag,text){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;return node;}
function svgElement(tag,attrs){const node=document.createElementNS(NS,tag);for(const [key,value]of Object.entries(attrs))node.setAttribute(key,String(value));return node;}

/** Pixel geometry stays in this view. It is never added to the AI upload payload. */
export function createCenteringView(panel){
 const image=panel.querySelector('[data-photo-image]'),preview=panel.querySelector('[data-photo-preview]');
 const section=panel.querySelector('[data-photo-centering]');
 if(!image||!preview||!section)return {setPhoto(){},clear(){},destroy(){}};
 const stage=element('div');stage.className='centering-stage';image.before(stage);stage.append(image);
 const svg=svgElement('svg',{'aria-label':'Card edge and printed border guides',class:'centering-overlay'});stage.append(svg);
 const outlines={outer:svgElement('polygon',{class:'centering-outer',fill:'none'}),inner:svgElement('polygon',{class:'centering-inner',fill:'none'})};svg.append(outlines.outer,outlines.inner);
 const handles=[];
 for(let index=0;index<4;index++){
  const circle=svgElement('circle',{r:7,tabindex:0,role:'button',class:'centering-handle','aria-label':corners[index]+' guide. Arrow keys move one pixel; Shift moves ten.'});svg.append(circle);handles.push(circle);
 }
 const title=element('h4','Centering from this photo');
 const status=element('p');status.setAttribute('role','status');status.setAttribute('aria-live','polite');status.className='centering-status';
 const values=element('p');values.className='centering-values';values.hidden=true;
 const details=element('details'),summary=element('summary','Inspect or adjust the border guides');details.append(summary);
 const help=element('p','Match the outside outline to the card edges and the inside outline to the printed frame. Drag a handle, or focus it and use the arrow keys. Adjust both outlines before confirming.');
 const label=element('label','Adjust '),layer=element('select');
 for(const [value,text]of [['inner','Printed frame'],['outer','Card edges']]){const option=element('option',text);option.value=value;layer.append(option);}label.append(layer);
 const apply=element('button','Use these guides');apply.type='button';apply.className='btn btn-outline';
 const reset=element('button','Restore automatic guides');reset.type='button';reset.className='text-link';
 const actions=element('div');actions.className='centering-actions';actions.append(apply,reset);
 details.append(help,label,actions);section.replaceChildren(title,status,values,details);
 let revision=0,photo=null,original=null,quad=null,active='inner',pointer=null,dirty=false,destroyed=false;
 const listeners=new AbortController();
 const listen=(node,name,handler)=>node.addEventListener(name,handler,{signal:listeners.signal});
 function paint(){
  if(!photo||!quad||(!details.open&&original?.status!=='measured')){svg.toggleAttribute('hidden',true);return;}
  svg.toggleAttribute('hidden',false);svg.setAttribute('viewBox',`0 0 ${photo.width} ${photo.height}`);
  for(const key of ['outer','inner'])outlines[key].setAttribute('points',quad[key].map(p=>p.x+','+p.y).join(' '));
  handles.forEach((handle,i)=>{handle.setAttribute('cx',quad[active][i].x);handle.setAttribute('cy',quad[active][i].y);handle.toggleAttribute('hidden',!details.open);handle.setAttribute('r',Math.max(7,photo.width/(stage.getBoundingClientRect().width||260)*12));handle.setAttribute('aria-label',active+' '+corners[i]+' guide. Arrow keys move one pixel; Shift moves ten.');});
  svg.classList.toggle('centering-editing',details.open);
 }
 function showMeasurement(result,source){
  if(result.status!=='measured'){
   values.hidden=true;values.textContent='';status.textContent=result.reason||'The outlines do not define a usable border. Adjust the guides or take another photo.';return;
  }
  const b=result.borders,r=result.ratios;
  const sourceText=source==='automatic'?'Automatically detected':'From the guides you confirmed';
  status.textContent=sourceText+'. Inspect the outlines before using these ratios.';
  const variation=result.uncertainty&&Math.max(result.uncertainty.leftRight??0,result.uncertainty.topBottom??0);
  values.textContent=`Left / right: ${r.left} / ${r.right}. Top / bottom: ${r.top} / ${r.bottom}. Borders in rectified image pixels: left ${Math.round(b.left)}, right ${Math.round(b.right)}, top ${Math.round(b.top)}, bottom ${Math.round(b.bottom)}.`+(variation?` Boundary sensitivity: about ±${Math.ceil(variation)} percentage points; this is not calibrated measurement accuracy.`:'');
  values.hidden=false;
 }
 function setInitialGuides(result){
  const w=photo.width,h=photo.height;
  const outer=result.outerQuad??[{x:w*.05,y:h*.05},{x:w*.95,y:h*.05},{x:w*.95,y:h*.95},{x:w*.05,y:h*.95}];
  const inner=result.innerQuad??outer.map((p,i)=>({x:p.x+(i===0||i===3?w*.055:-w*.055),y:p.y+(i<2?h*.055:-h*.055)}));
  quad={outer:copy(outer),inner:copy(inner)};
 }
 function clear(){
  revision++;photo=null;quad=null;original=null;pointer=null;dirty=false;section.hidden=true;svg.toggleAttribute('hidden',true);svg.replaceChildren(outlines.outer,outlines.inner,...handles);values.hidden=true;values.textContent='';status.textContent='';details.open=false;
 }
 async function setPhoto(next){
  clear();const current=revision;photo=next;section.hidden=false;status.textContent='Checking the card edges and printed frame…';
  stage.style.aspectRatio=next.width+' / '+next.height;
  try{
   await image.decode();if(destroyed||current!==revision)return;
   const canvas=document.createElement('canvas');canvas.width=next.width;canvas.height=next.height;
   const ctx=canvas.getContext('2d',{willReadFrequently:true});if(!ctx)throw Error('Canvas unavailable');ctx.drawImage(image,0,0);
   const result=detectCardCentering(ctx.getImageData(0,0,next.width,next.height));
   if(destroyed||current!==revision)return;
   original=result;setInitialGuides(result);showMeasurement(result,'automatic');reset.hidden=result.status!=='measured';apply.disabled=true;paint();
   if(result.status!=='measured')status.textContent='Automatic measurement unavailable. '+(result.reason||'A continuous printed border could not be found.')+' You can adjust the guides or use the manual calculator below.';
  }catch{if(!destroyed&&current===revision){setInitialGuides({});status.textContent='This photo could not be measured automatically. Adjust the guides or use the manual calculator below.';reset.hidden=true;apply.disabled=true;paint();}}
 }
 function moved(index,x,y){
  if(!quad||!photo)return;quad[active][index]={x:Math.max(0,Math.min(photo.width-1,x)),y:Math.max(0,Math.min(photo.height-1,y))};dirty=true;apply.disabled=false;values.hidden=true;status.textContent='Guides changed. Match both outlines to the actual borders, then choose Use these guides.';paint();
 }
 function coordinates(event){const rect=svg.getBoundingClientRect();return {x:(event.clientX-rect.left)/rect.width*photo.width,y:(event.clientY-rect.top)/rect.height*photo.height};}
 handles.forEach((handle,index)=>{
  listen(handle,'pointerdown',event=>{if(!details.open||!quad)return;event.preventDefault();pointer={id:event.pointerId,index};handle.setPointerCapture(event.pointerId);});
  listen(handle,'pointermove',event=>{if(pointer?.id!==event.pointerId||pointer.index!==index||!photo)return;const p=coordinates(event);moved(index,p.x,p.y);});
  for(const eventName of ['pointerup','pointercancel','lostpointercapture'])listen(handle,eventName,()=>{pointer=null;});
  listen(handle,'keydown',event=>{
   if(!quad||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;event.preventDefault();const amount=event.shiftKey?10:1,p=quad[active][index];moved(index,p.x+(event.key==='ArrowLeft'?-amount:event.key==='ArrowRight'?amount:0),p.y+(event.key==='ArrowUp'?-amount:event.key==='ArrowDown'?amount:0));
  });
 });
 listen(details,'toggle',paint);listen(layer,'change',()=>{active=layer.value;paint();});
 listen(apply,'click',()=>{if(!dirty||!quad)return;showMeasurement(measureFromQuads(quad.outer,quad.inner),'manual');});
 listen(reset,'click',()=>{if(!original||!photo)return;setInitialGuides(original);dirty=false;apply.disabled=true;showMeasurement(original,'automatic');paint();});
 clear();return {setPhoto,clear,destroy(){destroyed=true;clear();listeners.abort();stage.replaceWith(image);section.replaceChildren();}};
}
