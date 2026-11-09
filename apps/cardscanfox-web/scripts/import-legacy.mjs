import { readFile,writeFile,mkdir } from 'node:fs/promises';
import { parse,serialize,serializeOuter } from 'parse5';
import { createHash } from 'node:crypto';
const topics=JSON.parse(await readFile(new URL('../content/blog-topics.json',import.meta.url),'utf8'));
const source=new URL('../content/legacy/',import.meta.url);
const output=new URL('../../../packages/website-content/data/legacy-pages.json',import.meta.url);
const baseline=JSON.parse(await readFile(new URL('source-baseline.json',source),'utf8'));
const walk=(node,fn)=>{fn(node);for(const c of node.childNodes??[])walk(c,fn);};
const attr=(node,key)=>node.attrs?.find(a=>a.name===key)?.value;
const text=node=>node.nodeName==='#text'?node.value:(node.childNodes??[]).map(text).join('');
const find=(node,fn)=>{let result;walk(node,n=>{if(!result&&fn(n))result=n;});return result;};
const norm=value=>value.replace(/\s+/g,' ').trim();
const visibleText=node=>['script','style','noscript'].includes(node.tagName)?'':node.nodeName==='#text'?node.value:(node.childNodes??[]).map(visibleText).join('');
const clean=node=>{
 node.childNodes=(node.childNodes??[]).filter(c=>!['script','style','noscript','iframe','object','embed'].includes(c.tagName));
 for(const c of node.childNodes){
  if(c.attrs)c.attrs=c.attrs.filter(a=>!a.name.startsWith('on')&&a.name!=='style'&&a.name!=='srcdoc').map(a=>{
   if(['href','src'].includes(a.name)){
    if(/^javascript:|^vbscript:/i.test(a.value))return {...a,value:'#'};
    if(a.value.startsWith('https://tcgcard.fun/'))return {...a,value:a.value.slice('https://tcgcard.fun'.length)};
    if(a.name==='src'&&a.value.startsWith('/assets/'))return {...a,value:a.value.replace('/assets/','/assets/legacy/')};
   }
   return a;
  });
  clean(c);
 }
};
const records=[];
for(const page of baseline.pages){
 const original=await readFile(new URL(page.file,source),'utf8');if(createHash('sha256').update(original).digest('hex')!==page.htmlSha256)throw new Error(`Source changed: ${page.path}`);
 const doc=parse(original),main=find(doc,n=>n.tagName==='main');if(!main)throw new Error(`No main content: ${page.path}`);
 const sourceText=norm(visibleText(main));const ld=[];walk(doc,n=>{if(n.tagName==='script'&&attr(n,'type')==='application/ld+json'){try{ld.push(JSON.parse(text(n)));}catch{throw new Error(`Invalid source JSON-LD: ${page.path}`);}}});
 clean(main);walk(main,n=>{if((attr(n,'class')??'').split(/\s+/).includes('blog-card')){const a=find(n,x=>x.tagName==='a'&&attr(x,'href'));const topic=topics[attr(a??{},'href')];if(topic)n.attrs.push({name:'data-topic',value:topic});}});const sanitizedText=norm(visibleText(main));if(sanitizedText!==sourceText)throw new Error(`Visible source content changed during import: ${page.path}`);
 const title=text(find(doc,n=>n.tagName==='title')??{});const description=attr(find(doc,n=>n.tagName==='meta'&&attr(n,'name')==='description')??{},'content')??'';
 const h1=text(find(main,n=>n.tagName==='h1')??{}),headings=[],links=[],images=[],dates=[];walk(main,n=>{if(n.tagName==='h2')headings.push(norm(text(n)));if(n.tagName==='a'&&attr(n,'href'))links.push(attr(n,'href'));if(n.tagName==='img')images.push({src:attr(n,'src'),alt:attr(n,'alt')??''});if(n.tagName==='time')dates.push({date:attr(n,'datetime'),text:text(n)});});
 records.push({category:topics[page.path]??null,id:'legacy-'+String(records.length+1).padStart(2,'0'),path:page.path,type:page.path==='/'?'home':page.path==='/blog/'?'blog-index':page.path.startsWith('/blog/')?'article':page.path.includes('-vs-')||page.path.includes('comparison-2026')?'comparison':['/privacy','/terms'].includes(page.path)?'legal':'feature',title,description,h1,bodyHtml:serialize(main),sourceBodyHash:createHash('sha256').update(sourceText).digest('hex'),sourceHtmlHash:page.htmlSha256,canonical:page.canonical??`https://tcgcard.fun${page.path}`,headings,jsonLd:ld,links:[...new Set(links)],images,dates,protected:true,importedFrom:'https://tcgcard.fun'+page.path,capturedOn:baseline.capturedOn});
}
await mkdir(new URL('.',output),{recursive:true});await writeFile(output,JSON.stringify(records,null,2)+'\n');
console.log(`Imported ${records.length} complete legacy pages; visible main text is unchanged.`);
