/** Keep only public response context; never expose an upstream body or connection. */
export class CatalogResponseError extends Error {
 constructor(response) {
  super('CATALOG_UNAVAILABLE');
  this.name='CatalogResponseError';
  this.upstreamStatus=response.status;
  this.reason=response.status===429?'UPSTREAM_RATE_LIMITED':'UPSTREAM_UNAVAILABLE';
  this.retryAfter=[429,503].includes(response.status)?validRetryAfter(response.headers.get('Retry-After')):null;
 }
}

function validRetryAfter(value) {
 if(!value)return null;
 if(/^(?:0|[1-9]\d{0,4})$/.test(value)&&Number(value)<=86400)return value;
 if(!/^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$/.test(value))return null;
 const parsed=Date.parse(value);
 return Number.isFinite(parsed)&&new Date(parsed).toUTCString()===value?value:null;
}
