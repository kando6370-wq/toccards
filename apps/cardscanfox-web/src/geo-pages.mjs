import { appStoreUrl, googlePlayUrl, publicOrigin } from '@kando/website-content';

export const brandDescription = 'CardScanFox is an AI-powered trading card scanner and collection management platform that helps collectors identify trading cards, explore card prices, and manage their collections across multiple TCG and sports card categories.';

const schemaContext = 'https://schema.org';
const organizationId = publicOrigin + '/#organization';
const appId = publicOrigin + '/app#mobile-app';

export const organizationSchema = {
 '@context': schemaContext,
 '@type': 'Organization',
 '@id': organizationId,
 name: 'CardScanFox',
 url: publicOrigin + '/',
 logo: publicOrigin + '/assets/card-ai-icon.svg',
 description: brandDescription,
 contactPoint: { '@type': 'ContactPoint', contactType: 'customer support', email: 'support@tcgcard.fun' },
};

export const mobileAppSchema = {
 '@context': schemaContext,
 '@type': 'SoftwareApplication',
 '@id': appId,
 name: 'CardScanFox',
 alternateName: 'Card AI: TCG Card Scanner',
 url: publicOrigin + '/app',
 operatingSystem: ['iOS', 'Android'],
 applicationCategory: 'ReferenceApplication',
 installUrl: appStoreUrl,
 sameAs: [googlePlayUrl],
 description: brandDescription,
 publisher: { '@id': organizationId, name: 'CardScanFox' },
 featureList: ['AI-assisted trading card identification', 'Card price lookup', 'Portfolio and Wishlist management'],
};

export function breadcrumbSchema(items) {
 return {
  '@context': schemaContext,
  '@type': 'BreadcrumbList',
  itemListElement: items.map(([path, name], index) => ({
   '@type': 'ListItem',
   position: index + 1,
   name,
   item: publicOrigin + path,
  })),
 };
}

const competitors = [
 ['/blog/cardscanfox-vs-collectr', 'Collectr', 'Choose by the work you do after adding a card to your portfolio. Compare printing review, collection records and value tracking.'],
 ['/card-ai-vs-ludex', 'Ludex', 'Compare scan review and collection management with a workflow that can also prepare eBay listings.'],
 ['/card-ai-vs-collx', 'CollX', 'Compare how each tool handles variants, collection records and selling.'],
 ['/blog/cardscanfox-vs-tcgplayer', 'TCGplayer', 'Compare a collection workflow with marketplace listings and a published market price.'],
 ['/blog/cardscanfox-vs-pricecharting', 'PriceCharting', 'Compare app-based collection tracking with research into historical sales and grade-specific prices.'],
];

const pages = {
 '/about': {
  heading: 'About CardScanFox',
  title: 'About CardScanFox | AI Trading Card Scanner',
  description: brandDescription,
  schema: [organizationSchema, mobileAppSchema],
  body: [
   ['What can I do with CardScanFox?', '<p>Use a card photo to find likely matches. Confirm the set, full collector number, language and finish. Then check the available price for that printing. In the mobile app, add the cards you own to Portfolio and the cards you want to Wishlist.</p><p>The app helps collectors organize binders and boxes, compare copies before buying or selling, and follow available price changes. The website also lets you search the card catalog by name, set or number.</p>'],
   ['Card categories and platforms', '<p>Browse Pokémon, Magic: The Gathering, One Piece, Yu-Gi-Oh!, Disney Lorcana and selected sports cards such as basketball. Check the catalog for your exact card because coverage and prices vary by set and printing.</p><p>Find the mobile app as <strong>Card AI: TCG Card Scanner</strong> in the App Store and on Google Play. The website also has a single-photo scanner. The separate Chrome extension works on card images on webpages.</p><ul><li><a href="/games">Browse card categories</a></li><li><a href="/download">Download for iPhone, Android or Chrome</a></li><li><a href="/card-identifier">Identify a card from a photo</a></li></ul>'],
   ['Check the evidence behind a result', '<p>The scanner suggests catalog matches. Confirm the card before you save it or use its price. The separate photo pregrading tool estimates visible condition from front and back photos. Authentication and certified grades require a qualified service.</p><ul><li><a href="/ai-card-recognition-accuracy/">Recognition test method</a></li><li><a href="/card-price-data-methodology/">Card price data methodology</a></li><li><a href="/compare/">Compare card scanners</a></li><li><a href="/ai-card-grading">Visible-condition pregrading</a></li></ul>'],
   ['Support and product updates', '<p>Contact <a href="mailto:support@tcgcard.fun">support@tcgcard.fun</a> for help. For a card issue, include a public card page or the set and full number. For app changes and version history, see the store listing for your device.</p><ul><li><a href="/help">Help center</a></li><li><a href="/privacy">Privacy policy</a></li><li><a href="/terms">Terms of service</a></li><li><a href="' + appStoreUrl + '">App Store version history</a></li><li><a href="' + googlePlayUrl + '">Google Play listing</a></li></ul>'],
  ],
 },
 '/ai-card-recognition-accuracy/': {
  heading: 'AI card recognition benchmark',
  title: 'AI Card Recognition Benchmark Method | CardScanFox',
  description: 'See what a three-image web scanner check verified and how CardScanFox will measure Top 1, Top 3, exact printing and scan time on physical cards.',
  body: [
   ['What the web scanner check found', '<p>On 16 November 2026, we verified the live web workflow with three public catalog images using the web release built from commit <code>3099fbf9</code>. For each image, the first candidate matched the source card and the page returned five candidates. The check used catalog artwork under controlled input. A separate test with physical-card photos is required to measure accuracy, lighting effects, exact printing accuracy and time on real scans.</p><ul><li><a href="/cards/686490">General trading card scanner sample</a></li><li><a href="/cards/714372">Pokémon scanner sample</a></li><li><a href="/cards/t8546993">Sports card scanner sample</a></li></ul>'],
   ['A recorded web scan', '<p>On 24 November 2026, we selected the public catalog image for Charizard 4/102 in the live Pokémon web scanner. It returned five candidates. The first was the expected English Holofoil card from ME: 30th Celebration Classic Collection. The next candidate shared the name and number and belonged to a different set. Check the set before applying a price.</p><figure class="content-figure"><img src="/assets/recognition-example.jpg" width="850" height="462" loading="lazy" alt="First result from the live Pokémon scanner: English Holofoil Charizard 4/102, ME: 30th Celebration Classic Collection"><figcaption>Live web scanner result captured on 24 November 2026. The visible TCGplayer price is a dated reference.</figcaption></figure><p><a href="/pokemon-card-scanner">Try the same web scanner</a> or <a href="/cards/714372">open the matching card record</a>.</p>'],
   ['How the scan works', '<p>The web scanner turns one card-front photo into an image vector in the browser and uses that vector to retrieve possible matches from the card catalog. Review the matching artwork, set, collector number, language and finish on your copy. Scan results identify candidate catalog records. For a separate visible-condition estimate, use <a href="/ai-card-grading">the photo pregrading tool</a>.</p>'],
   ['How to collect the physical-card sample', '<ol><li>Choose physical cards with independently verified set, full number, language, artwork and finish. Record how many unique cards and photo attempts each group contains.</li><li>Group available samples by game or sport, language, normal or foil finish, and similar-looking printings. Include selected non-catalog cards and report them separately.</li><li>Capture the same cards in straight-on even light and repeat with sleeves, reflection, tilt and mild blur. Record device, platform, app or web release, capture conditions and date.</li><li>Keep the ground truth separate from the scan candidates. Score the first completed attempt for each photo and record errors, empty results and timeouts. Retain candidate order and elapsed time.</li></ol>'],
   ['How to calculate the results', '<div class="reference-table-wrap" role="region" aria-label="Recognition metrics" tabindex="0"><table><caption>Recognition metrics for photos of cataloged physical cards</caption><thead><tr><th scope="col">Metric</th><th scope="col">Calculation</th></tr></thead><tbody><tr><th scope="row">Top 1 identity</th><td>The first candidate has the correct game, set and collector number. Divide matches by all valid attempts, including failed attempts.</td></tr><tr><th scope="row">Top 3 identity</th><td>At least one of the first three candidates has the correct game, set and collector number. Use the same attempt count as Top 1.</td></tr><tr><th scope="row">Top 1 exact printing</th><td>The first candidate also matches the expected language, artwork and finish for the exact printing. Record incomplete candidate details separately.</td></tr><tr><th scope="row">Recognition time</th><td>Measure from scan submission to the first visible result. Report mean and 95th percentile for completed scans. Count errors and timeouts separately, and report first-load time separately from repeat scans.</td></tr></tbody></table></div><p>Report the numerator, denominator, sample groups, test date, version and device with each result. The physical-card sample and its results are awaiting collection.</p>'],
  ],
 },
 '/card-price-data-methodology/': {
  heading: 'Card price data methodology',
  title: 'Card Price Data Sources & Methodology | CardScanFox',
  description: 'See how CardScanFox selects card price references by source, printing, condition or slab grade, observation date and currency.',
  body: [
   ['Where the prices come from', '<p>CardScanFox reads active, published USD price series from its catalog. The selected price shows its provider and metric on the card page. Open a card such as <a href="/cards/714372">Pokémon Charizard 4/102</a> and expand its price source to see the provider and metric. Coverage varies by provider, game, set and printing. Read the source for your exact record.</p>'],
   ['Price references, listings and completed sales', '<p>A reference price summarizes or reproduces a provider’s published metric. A listing price is the amount a seller asks. A completed sale price is the amount recorded for one transaction. The provider’s metric determines how to interpret a reference. CardScanFox displays the series and observation date. Use the provider’s own methodology to check whether the series uses completed sales, listings or another input.</p><p>A provider’s published amount gives you a reference for comparison. Fees, shipping and the condition of your card can affect the amount you receive from a sale.</p><p>For definitions from common external providers, read TCGplayer price points, PriceCharting methodology and eBay Product Research.</p>'],
   ['Which fields identify a price', '<dl><dt>Card identity</dt><dd>Name, game, set, full collector number, language and finish, where available.</dd><dt>Card state</dt><dd>Raw condition or the grading company and grade printed on a slab.</dd><dt>Price context</dt><dd>Amount, currency, provider, provider metric and observation date. A series selection keeps these fields together.</dd></dl><p>The default card detail uses a raw price series when available. Use the selector for an available series that matches your copy. An English foil and a non-foil copy, or a Near Mint raw card and a PSA 9 copy, can belong to different series.</p>'],
   ['When prices update', '<p>A card page uses the latest active published batch available for the provider. Publication timing and coverage can vary. The observation date shows when the source recorded the value. The date you open the page can be later. The website shows available observations for the selected series in the 30 days ending on its latest observation.</p>'],
   ['Missing and unusual prices', '<p>If a matching price is unavailable, the card remains visible without a price. Missing days are omitted from the history. CardScanFox keeps each observed amount and its source context, so a large change needs a check against the exact printing, grade, date and provider. The seven-day gainers list requires comparable dates for the same raw series and excludes a missing or zero starting amount.</p><ul><li><a href="/data-methodology">Read the ranking and catalog data notes</a></li><li><a href="/card-price-checker">Look up a trading card price</a></li></ul>'],
  ],
 },
 '/compare/': {
  heading: 'Compare trading card scanners and price tools',
  title: 'Trading Card Scanner Comparisons | CardScanFox',
  description: 'Compare CardScanFox with Collectr, Ludex, CollX, TCGplayer and PriceCharting for your card identification, price research or collection workflow.',
  body: [
   ['Choose a tool for your next task', '<p>Use the guides below to compare scanning, printing coverage, available prices, collection features and plan limits. Each guide shows the sources for its product details. To measure speed or recognition accuracy, run the same physical-card photos through both products.</p>'],
   ['Five side-by-side guides', '<ul>' + competitors.map(([path, name, description]) => '<li><a href="' + path + '">CardScanFox vs ' + name + '</a><p>' + description + '</p></li>').join('') + '</ul>'],
   ['Try the same cards in each tool', '<p>Include one ordinary printing, one foil or parallel, and one existing graded slab. Check the candidate’s set and full number first. Then compare what the tool shows for price date, condition or grade, review queue and collection workflow. Check current plan limits before subscribing.</p><ul><li><a href="/card-scanner-comparison-2026">Read the wider scanner comparison</a></li><li><a href="/ai-card-recognition-accuracy/">Read the recognition test method</a></li><li><a href="/card-price-data-methodology/">Check what a price reference means</a></li></ul>'],
  ],
 },
};

export const geoPaths = Object.keys(pages);

export function renderGeoPage(path, shell) {
 const page = pages[path];
 const breadcrumbs = '<nav class="breadcrumbs" aria-label="Breadcrumb"><a href="/">Home</a><span aria-hidden="true">›</span><span aria-current="page">' + page.heading + '</span></nav>';
 const body = '<article class="legacy-content file-article">' + breadcrumbs + '<h1>' + page.heading + '</h1><p class="content-lede">' + page.description + '</p>' +
  page.body.map(([heading, content]) => '<section><h2>' + heading + '</h2>' + content + '</section>').join('') + '</article>';
 return shell({
  path,
  title: page.title,
  description: page.description,
  body,
  jsonLd: [breadcrumbSchema([['/', 'Home'], [path, page.heading]]), ...(page.schema ?? [])],
 });
}
