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

  return ownAppListings.some(listing =>
    url.origin === listing.origin &&
    url.pathname === listing.pathname &&
    (listing.search === '' || url.search === listing.search)
  );
}
