import { createWebsiteHandler, type WebsiteEnv } from './index';

// The existing Pages preview is public. It exposes only published catalog data.
// The separate Worker entry keeps its Basic authentication requirement.
const preview = createWebsiteHandler({publicPreview:true});
export default {
 fetch(request: Request, env: WebsiteEnv, context: ExecutionContext): Promise<Response> {
  return preview.fetch(request, {...env,DEPLOYMENT_MODE:'preview',CATALOG_MODE:'service',LOCAL_DEVELOPMENT:'false',PUBLISH_READY:'false'}, context);
 }
};
