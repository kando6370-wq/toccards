import {appStoreUrl, chromeStoreUrl, googlePlayUrl, publicOrigin} from '@kando/website-content';

const firstPartyHosts = new Set(['tcgcard.fun', 'www.tcgcard.fun', 'api.tcgcard.fun', 'image.tcgcard.fun']);
const ownAppListings = [appStoreUrl, googlePlayUrl, chromeStoreUrl].map(value => new URL(value));

export function isPublicLinkAllowed(href) {
  let url;
  try {
    url = new URL(href, publicOrigin);
  } catch {
    return false;
  }

  if (url.protocol === 'mailto:') return url.pathname === 'support@tcgcard.fun';
  if (url.protocol !== 'https:' || url.username || url.password) return false;
  if (firstPartyHosts.has(url.host)) return true;

  if (url.origin === 'https://chromewebstore.google.com' &&
    /^\/detail\/(?:cardscanfox-%E2%80%94-pok%C3%A9mon-tcg\/)?hggmhmclihnigdmgcbggblhmjjlpaemn\/reviews(?:\/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})?$/.test(url.pathname)) {
    return true;
  }

  return ownAppListings.some(listing =>
    url.origin === listing.origin &&
    url.pathname === listing.pathname &&
    (listing.search === '' || url.search === listing.search)
  );
}
