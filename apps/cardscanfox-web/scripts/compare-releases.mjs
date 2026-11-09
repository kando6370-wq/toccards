import { compareReleases } from './release-tools.mjs';
const [current,candidate]=process.argv.slice(2);
if(!current||!candidate)throw new Error('Usage: release:compare <current-release-directory> <candidate-release-directory>');
const result=await compareReleases(current,candidate);console.log(JSON.stringify(result,null,2));if(!result.safe)process.exitCode=1;
