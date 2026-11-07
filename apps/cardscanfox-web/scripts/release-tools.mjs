import { readFile, readdir } from 'node:fs/promises';
import { resolve, sep } from 'node:path';
import { createHash } from 'node:crypto';
export const hash = value => createHash('sha256').update(value).digest('hex');
export async function inventory(root, relative = '') {
 const files=[];
 for(const entry of await readdir(resolve(root,relative),{withFileTypes:true})){
  const path=relative?relative+'/'+entry.name:entry.name;
  if(entry.isSymbolicLink())throw new Error('Release assets cannot contain symbolic links.');
  if(entry.isDirectory())files.push(...await inventory(root,path));
  else if(entry.isFile()&&entry.name!=='release-manifest.json') {const body=await readFile(resolve(root,path));files.push({path,bytes:body.length,sha256:hash(body)});}
 }
 return files.sort((a,b)=>a.path.localeCompare(b.path));
}
export function releaseFingerprint(manifest) {return hash(JSON.stringify({schemaVersion:manifest.schemaVersion,catalogVersion:manifest.catalogVersion,runtimeSources:manifest.runtimeSources,routes:manifest.routes,files:manifest.files}));}
export async function verifyRelease(root) {
 root=resolve(root);const manifest=JSON.parse(await readFile(resolve(root,'release-manifest.json'),'utf8'));
 if(manifest.schemaVersion!==1||!Array.isArray(manifest.routes)||!Array.isArray(manifest.files)||releaseFingerprint(manifest)!==manifest.releaseId)throw new Error('Invalid release manifest.');
 const seen=new Set();
 for(const f of manifest.files){const target=resolve(root,f.path);if(!target.startsWith(root+sep)||seen.has(f.path))throw new Error('Unsafe or duplicate release file.');seen.add(f.path);const bytes=await readFile(target);if(bytes.length!==f.bytes||hash(bytes)!==f.sha256)throw new Error('Release asset mismatch: '+f.path);}
 if(JSON.stringify(await inventory(root))!==JSON.stringify(manifest.files))throw new Error('Release contains unregistered files.');
 if(new Set(manifest.routes.map(r=>r.path)).size!==manifest.routes.length||manifest.routes.some(r=>!seen.has(r.file)))throw new Error('Release route inventory is inconsistent.');
 return manifest;
}
export async function compareReleases(currentRoot,candidateRoot){
 const current=await verifyRelease(currentRoot),candidate=await verifyRelease(candidateRoot);const next=new Map(candidate.routes.map(r=>[r.path,r]));
 const missing=current.routes.filter(r=>!next.has(r.path)).map(r=>r.path);
 const changedProtected=current.routes.filter(r=>r.protected&&(!next.get(r.path)?.protected||r.sourceBodyHash!==next.get(r.path)?.sourceBodyHash)).map(r=>r.path);
 return {safe:missing.length===0&&changedProtected.length===0,currentRelease:current.releaseId,candidateRelease:candidate.releaseId,missing,changedProtected,added:candidate.routes.filter(r=>!current.routes.some(p=>p.path===r.path)).map(r=>r.path)};
}
