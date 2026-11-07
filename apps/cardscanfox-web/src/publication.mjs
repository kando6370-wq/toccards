import policy from '../content/index-policy.json' with {type:'json'};
import {legacyByPath,allStaticPaths} from './render.mjs';
const approved=new Set(policy.newIndexPaths);
export function mayIndex(url,status=200,page={}) {
 if(status!==200||url.search||url.pathname==='/saved')return false;
 if(/^\/cards\/[^/]+$/.test(url.pathname))return policy.catalog?.enabled===true&&page.seo?.kind==='card'&&page.seo.eligible===true;
 if(page.dataAvailable===false&&!legacyByPath.has(url.pathname))return false;
 if(/^\/(games|sets)\/[^/]+$/.test(url.pathname)&&page.dataAvailable===true)return true;
 return legacyByPath.has(url.pathname)||approved.has(url.pathname);
}
export function publishHtml(html,url,status,page={}) {
 const robots=mayIndex(url,status,page)?'index,follow':'noindex,follow';
 return html.replace(/<meta name="robots" content="[^"]*">/,`<meta name="robots" content="${robots}">`).replace(/<div class="preview-rail">[\s\S]*?<\/div>/,'').replace('CardScanFox is the proposed website identity for the existing Card AI app.','CardScanFox is the website for the Card AI app.');
}
const escape=s=>s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
export function publicSitemap(origin='https://tcgcard.fun') {
 const paths=[...new Set([...legacyByPath.keys(),...approved])];
 return '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'+paths.filter(path=>mayIndex(new URL(path,origin))).map(path=>`<url><loc>${escape(origin+path)}</loc></url>`).join('\n')+'\n</urlset>\n';
}
export function sitemapIndex(shards=[],origin='https://tcgcard.fun') {
 if(shards.length>50000-1)throw new Error('Too many sitemap files.');
 const paths=['/sitemaps/site.xml',...shards.map(s=>s.path)];
 if(new Set(paths).size!==paths.length||shards.some(s=>!/^\/sitemaps\/cards-\d{5}\.xml$/.test(s.path)))throw new Error('Invalid sitemap manifest path.');
 return '<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'+paths.map(path=>`<sitemap><loc>${escape(origin+path)}</loc></sitemap>`).join('\n')+'\n</sitemapindex>\n';
}
export function validateIndexPolicy() {
 if(!Array.isArray(policy.newIndexPaths)||policy.newIndexPaths.some(p=>!allStaticPaths.includes(p)||p==='/saved'||p.includes('?')||p.includes('#')||p.includes('/category/opinion')))throw new Error('Index policy contains an unknown or ineligible route.');
 if(policy.catalog?.enabled!==true&&policy.catalog?.enabled!==false)throw new Error('Catalog eligibility policy must be explicit.');
}
