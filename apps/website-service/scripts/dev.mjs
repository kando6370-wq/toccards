import {build} from 'esbuild';
import {mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {startLocalServer} from '@kando/website-content/node-server';
await mkdir(new URL('../.local/',import.meta.url),{recursive:true});
await build({entryPoints:[fileURLToPath(new URL('../src/worker.ts',import.meta.url))],bundle:true,platform:'node',format:'esm',target:'es2022',outfile:fileURLToPath(new URL('../.local/worker.mjs',import.meta.url))});
const worker=(await import('../.local/worker.mjs?'+Date.now())).default;
startLocalServer(worker,{DEPLOYMENT_MODE:'preview',CATALOG_MODE:process.env.CATALOG_MODE??'snapshot',LOCAL_CATALOG_DATABASE_URL:process.env.SITE_CATALOG_DATABASE_URL??''},{port:Number(process.env.SITE_DATA_PORT??8891),label:'CardScanFox independent read service'});
