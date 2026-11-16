/*
 * ETB quote calculator. Monetary inputs use integer USD cents.
 * Saved listings are dated observations, not live stock or checkout quotes.
 * This module has no network, storage, DOM, model or framework dependency.
 * The website client and server-rendered form share these dated examples.
 */

export const ETB_SNAPSHOT_DATE = '2026-11-16';

export const ETB_EDITIONS = Object.freeze({
  regular: Object.freeze({ label: 'Regular ETB', packsPerBox: 9, promosPerBox: 1, centerLogoPromosPerBox: 0 }),
  'pokemon-center': Object.freeze({ label: 'Pokémon Center ETB', packsPerBox: 11, promosPerBox: 2, centerLogoPromosPerBox: 1 }),
});

const SINGLE_URL = 'https://www.tcgplayer.com/product/712102/pokemon-me06-delta-reign-delta-reign-elite-trainer-box?Language=English';
const CASE_URL = 'https://www.tcgplayer.com/product/712103/pokemon-me06-delta-reign-delta-reign-elite-trainer-box-case?Language=English';
const PC_URL = 'https://www.pokemoncenter.com/product/10-10438-112/pokemon-tcg-mega-evolution-delta-reign-pokemon-center-elite-trainer-box';
const GS_URL = 'https://www.gamestop.com/toys-games/trading-cards/products/pokemon-trading-card-game-delta-reign-elite-trainer-box/20037568.html';

// A shipping amount displayed on a product row is not silently expanded into
// a verified multi-item cart quote. Null means that the order amount is unknown.
export const ETB_SNAPSHOT_OFFERS = Object.freeze([
  Object.freeze({
    id: 'great-buys-single', label: 'TCGplayer · Great Buys', editionId: 'regular',
    saleUnit: 'box', boxesPerSaleUnit: 1, minSaleUnits: 1, priceCents: 8498,
    shipping: Object.freeze({ kind: 'included', amountCents: 0, quotedSaleUnits: 1 }),
    availability: 'listed_snapshot', membershipRequired: false,
    observedMaxSaleUnits: 15, purchaseLimitBoxes: null,
    sourceUrl: SINGLE_URL, observedOn: ETB_SNAPSHOT_DATE,
    evidenceIds: ['ETB-C056', 'ETB-C057', 'ETB-C063'],
    note: 'The saved seller row advertised $84.98 with shipping included. Its displayed quantity was 15; current inventory and checkout tax were not verified.',
  }),
  Object.freeze({
    id: 'san-diego-min-three', label: 'TCGplayer · San Diego Dawg', editionId: 'regular',
    saleUnit: 'box', boxesPerSaleUnit: 1, minSaleUnits: 3, priceCents: 8000,
    shipping: Object.freeze({ kind: 'quote_requires_confirmation', amountCents: 399, quotedSaleUnits: null }),
    availability: 'listed_snapshot', membershipRequired: false,
    observedMaxSaleUnits: 3, purchaseLimitBoxes: null,
    sourceUrl: SINGLE_URL, observedOn: ETB_SNAPSHOT_DATE,
    evidenceIds: ['ETB-C058', 'ETB-C059', 'ETB-C060', 'ETB-C063'],
    note: 'The row displayed $80 per box, $3.99 shipping and a minimum of three. The saved page did not verify shipping for the final three-box cart. Confirm an order-level shipping amount to calculate its delivered subtotal.',
  }),
  Object.freeze({
    id: 'xaobx-ten-box-case', label: 'TCGplayer · xAoBx Card Shop case', editionId: 'regular',
    saleUnit: 'case', boxesPerSaleUnit: 10, minSaleUnits: 1, priceCents: 71196,
    shipping: Object.freeze({ kind: 'known_order', amountCents: 500, quotedSaleUnits: 1 }),
    availability: 'listed_snapshot', membershipRequired: false,
    observedMaxSaleUnits: 1, purchaseLimitBoxes: null,
    sourceUrl: CASE_URL, observedOn: ETB_SNAPSHOT_DATE,
    evidenceIds: ['ETB-C039', 'ETB-C042', 'ETB-C043'],
    note: 'This listing describes ten ETBs in a case and advertised one case at $711.96 plus $5 shipping. Confirm the exact seller unit. Additional cases and their shipping are not covered by this observation.',
  }),
  Object.freeze({
    id: 'pokemon-center-official', label: 'Pokémon Center official listing', editionId: 'pokemon-center',
    saleUnit: 'box', boxesPerSaleUnit: 1, minSaleUnits: 1, priceCents: 5999,
    shipping: Object.freeze({ kind: 'unknown', amountCents: null, quotedSaleUnits: null }),
    availability: 'unavailable', membershipRequired: false,
    observedMaxSaleUnits: null, purchaseLimitBoxes: 2,
    sourceUrl: PC_URL, observedOn: ETB_SNAPSHOT_DATE,
    evidenceIds: ['ETB-C004', 'ETB-C005', 'ETB-C015', 'ETB-C016', 'ETB-C017'],
    note: 'The official page displayed $59.99, UNAVAILABLE and a limit of two. Its low reference amount must not be presented as a currently buyable offer.',
  }),
  Object.freeze({
    id: 'gamestop-standard', label: 'GameStop', editionId: 'regular',
    saleUnit: 'box', boxesPerSaleUnit: 1, minSaleUnits: 1, priceCents: 9999,
    shipping: Object.freeze({ kind: 'unknown', amountCents: null, quotedSaleUnits: null }),
    availability: 'location_required', membershipRequired: false,
    observedMaxSaleUnits: null, purchaseLimitBoxes: null,
    sourceUrl: GS_URL, observedOn: ETB_SNAPSHOT_DATE,
    evidenceIds: ['ETB-C031', 'ETB-C034'],
    note: 'The saved listing displayed $99.99. Shipping and availability depended on the selected condition and location.',
  }),
  Object.freeze({
    id: 'gamestop-pro', label: 'GameStop Pro', editionId: 'regular',
    saleUnit: 'box', boxesPerSaleUnit: 1, minSaleUnits: 1, priceCents: 9499,
    shipping: Object.freeze({ kind: 'unknown', amountCents: null, quotedSaleUnits: null }),
    availability: 'location_required', membershipRequired: true,
    observedMaxSaleUnits: null, purchaseLimitBoxes: null,
    sourceUrl: GS_URL, observedOn: ETB_SNAPSHOT_DATE,
    evidenceIds: ['ETB-C032', 'ETB-C033', 'ETB-C034'],
    note: 'The saved $94.99 offer required Pro membership. No membership fee is amortized into the box price, and shipping or stock is not assumed.',
  }),
]);

function integer(value, name, minimum = 0) {
  if (!Number.isSafeInteger(value) || value < minimum) {
    throw new TypeError(`${name} must be a safe integer greater than or equal to ${minimum}.`);
  }
  return value;
}

function optionalCents(value, name) {
  return value === null || value === undefined || value === '' ? null : integer(value, name);
}

function checkedProduct(a, b, name) {
  const result = a * b;
  if (!Number.isSafeInteger(result)) throw new RangeError(`${name} is too large.`);
  return result;
}

function checkedSum(a, b, name) {
  const result = a + b;
  if (!Number.isSafeInteger(result)) throw new RangeError(`${name} is too large.`);
  return result;
}

function quoteRatio(cents, units) {
  if (cents === null) return null;
  return Object.freeze({ numeratorCents: cents, denominator: units, roundedCents: Math.round(cents / units) });
}

function validateOffer(offer) {
  if (!offer || typeof offer !== 'object') throw new TypeError('An offer object is required.');
  if (!ETB_EDITIONS[offer.editionId]) throw new TypeError('Unknown editionId.');
  if (!['box', 'case'].includes(offer.saleUnit)) throw new TypeError('saleUnit must be box or case.');
  integer(offer.boxesPerSaleUnit, 'boxesPerSaleUnit', 1);
  if (offer.saleUnit === 'box' && offer.boxesPerSaleUnit !== 1) throw new TypeError('A box sale unit must contain one box.');
  integer(offer.minSaleUnits, 'minSaleUnits', 1);
  integer(offer.priceCents, 'priceCents');
  if (!offer.shipping || !['included', 'known_order', 'quote_requires_confirmation', 'unknown'].includes(offer.shipping.kind)) {
    throw new TypeError('A recognized shipping.kind is required.');
  }
  if (offer.shipping.kind === 'included' && offer.shipping.amountCents !== 0) throw new TypeError('Included shipping must explicitly be zero.');
  if (['known_order', 'quote_requires_confirmation'].includes(offer.shipping.kind)) integer(offer.shipping.amountCents, 'shipping.amountCents');
  if (offer.shipping.kind === 'known_order') integer(offer.shipping.quotedSaleUnits, 'shipping.quotedSaleUnits', 1);
  if (offer.shipping.kind === 'unknown' && offer.shipping.amountCents != null) throw new TypeError('Unknown shipping must not contain a known amount. Use quote_requires_confirmation for an unconfirmed displayed amount.');
  if (!['listed_snapshot', 'unavailable', 'location_required', 'unknown'].includes(offer.availability)) throw new TypeError('A recognized availability state is required.');
  if (typeof offer.membershipRequired !== 'boolean') throw new TypeError('membershipRequired must be true or false.');
  if (offer.observedMaxSaleUnits !== null && offer.observedMaxSaleUnits !== undefined) integer(offer.observedMaxSaleUnits, 'observedMaxSaleUnits', 1);
  if (offer.purchaseLimitBoxes !== null && offer.purchaseLimitBoxes !== undefined) integer(offer.purchaseLimitBoxes, 'purchaseLimitBoxes', 1);
}

/**
 * request = { desiredBoxes, budgetCents?: number|null, editionId?: 'regular'|'pokemon-center'|'any', proMember?: boolean|null }
 * adjustments = { shippingCents?: number|null, shippingConfirmedForOrder?: boolean, taxCents?: number|null }
 * A blank tax input stays unknown. Explicitly entering zero is a user assumption.
 * A shipping override is applied only after confirmation for the computed order.
 */
export function calculateEtbOffer(offer, request, adjustments = {}) {
  validateOffer(offer);
  if (!request || typeof request !== 'object') throw new TypeError('A request object is required.');
  const desiredBoxes = integer(request.desiredBoxes, 'desiredBoxes', 1);
  const budgetCents = optionalCents(request.budgetCents, 'budgetCents');
  const selectedEdition = request.editionId ?? 'any';
  if (selectedEdition !== 'any' && !ETB_EDITIONS[selectedEdition]) throw new TypeError('Unknown requested editionId.');
  if (request.proMember !== null && request.proMember !== undefined && typeof request.proMember !== 'boolean') throw new TypeError('proMember must be true, false or null.');
  const overrideShippingCents = optionalCents(adjustments.shippingCents, 'adjustments.shippingCents');
  const taxCents = optionalCents(adjustments.taxCents, 'adjustments.taxCents');
  if (adjustments.shippingConfirmedForOrder !== undefined && typeof adjustments.shippingConfirmedForOrder !== 'boolean') throw new TypeError('shippingConfirmedForOrder must be true or false.');

  const saleUnits = Math.max(offer.minSaleUnits, Math.ceil(desiredBoxes / offer.boxesPerSaleUnit));
  const actualBoxes = checkedProduct(saleUnits, offer.boxesPerSaleUnit, 'actualBoxes');
  const edition = ETB_EDITIONS[offer.editionId];
  const totalPacks = checkedProduct(actualBoxes, edition.packsPerBox, 'totalPacks');
  const goodsCents = checkedProduct(saleUnits, offer.priceCents, 'goodsCents');
  let shippingCents = null;
  let shippingBasis = 'unknown';

  if (adjustments.shippingConfirmedForOrder === true && overrideShippingCents !== null) {
    shippingCents = overrideShippingCents;
    shippingBasis = 'user_confirmed_for_computed_order';
  } else if (offer.shipping.kind === 'included') {
    shippingCents = 0;
    shippingBasis = 'seller_listing_included';
  } else if (offer.shipping.kind === 'known_order' && saleUnits === offer.shipping.quotedSaleUnits) {
    shippingCents = offer.shipping.amountCents;
    shippingBasis = 'quoted_for_this_sale_unit_count';
  }

  const knownBeforeTaxTotalCents = shippingCents === null ? null : checkedSum(goodsCents, shippingCents, 'knownBeforeTaxTotalCents');
  const totalWithEnteredTaxCents = knownBeforeTaxTotalCents === null || taxCents === null ? null : checkedSum(knownBeforeTaxTotalCents, taxCents, 'totalWithEnteredTaxCents');
  // Unknown costs remain null in the total. The goods-only lower bound can still
  // establish that an order exceeds a budget before those costs are known.
  const knownLowerBoundCents = checkedSum(checkedSum(goodsCents, shippingCents ?? 0, 'knownLowerBoundCents'), taxCents ?? 0, 'knownLowerBoundCents');
  const missingAmounts = [];
  if (shippingCents === null) missingAmounts.push('order_shipping');
  if (taxCents === null) missingAmounts.push('checkout_tax');
  if (overrideShippingCents !== null && adjustments.shippingConfirmedForOrder !== true) missingAmounts.push('shipping_confirmation');

  const blockers = [];
  const conditions = [];
  if (selectedEdition !== 'any' && selectedEdition !== offer.editionId) blockers.push('different_selected_edition');
  if (offer.availability === 'unavailable') blockers.push('unavailable_in_saved_snapshot');
  else if (offer.availability === 'location_required') conditions.push('location_and_stock_check_required');
  else if (offer.availability === 'unknown') conditions.push('availability_not_established');
  else conditions.push('current_stock_not_checked');
  if (offer.membershipRequired && request.proMember === false) blockers.push('pro_membership_required');
  else if (offer.membershipRequired && request.proMember !== true) conditions.push('pro_membership_not_confirmed');
  if (offer.purchaseLimitBoxes != null && actualBoxes > offer.purchaseLimitBoxes) blockers.push('exceeds_observed_purchase_limit');
  if (offer.observedMaxSaleUnits != null && saleUnits > offer.observedMaxSaleUnits) blockers.push('exceeds_observed_seller_quantity');

  let budgetStatus = 'not_entered';
  if (budgetCents !== null) {
    if (knownLowerBoundCents > budgetCents) budgetStatus = 'over_budget';
    else if (totalWithEnteredTaxCents !== null) budgetStatus = 'within_entered_budget';
    else budgetStatus = 'needs_shipping_or_tax';
  }

  const quotedShippingScenario = offer.shipping.kind === 'quote_requires_confirmation'
    ? Object.freeze({
      kind: 'unconfirmed_order_shipping_assumption', shippingCents: offer.shipping.amountCents,
      beforeTaxTotalCents: checkedSum(goodsCents, offer.shipping.amountCents, 'quotedShippingScenario'),
      assumption: 'Only applies if checkout confirms that the displayed shipping amount covers this entire computed order.',
    }) : null;

  return Object.freeze({
    offerId: offer.id ?? null, label: offer.label ?? null, editionId: offer.editionId,
    desiredBoxes, saleUnit: offer.saleUnit, saleUnits, actualBoxes, extraBoxes: actualBoxes - desiredBoxes,
    packsPerBox: edition.packsPerBox, totalPacks,
    promosPerBox: edition.promosPerBox, totalPromos: checkedProduct(actualBoxes, edition.promosPerBox, 'totalPromos'),
    totalCenterLogoPromos: checkedProduct(actualBoxes, edition.centerLogoPromosPerBox, 'totalCenterLogoPromos'),
    pricePerSaleUnitCents: offer.priceCents, goodsCents, shippingCents, shippingBasis,
    enteredTaxCents: taxCents, taxBasis: taxCents === null ? 'not_entered' : 'user_entered_order_amount',
    knownBeforeTaxTotalCents, totalWithEnteredTaxCents, knownLowerBoundCents,
    perBoxBeforeTax: quoteRatio(knownBeforeTaxTotalCents, actualBoxes),
    perPackBeforeTax: quoteRatio(knownBeforeTaxTotalCents, totalPacks),
    perBoxWithEnteredTax: quoteRatio(totalWithEnteredTaxCents, actualBoxes),
    perPackWithEnteredTax: quoteRatio(totalWithEnteredTaxCents, totalPacks),
    goodsOnlyPerBox: quoteRatio(goodsCents, actualBoxes), goodsOnlyPerPack: quoteRatio(goodsCents, totalPacks),
    budgetCents, budgetStatus,
    budgetHeadroomBeforeTaxCents: budgetCents !== null && knownBeforeTaxTotalCents !== null ? budgetCents - knownBeforeTaxTotalCents : null,
    missingAmounts, blockers, conditions,
    snapshotEligible: blockers.length === 0,
    eligibilityFullyResolved: blockers.length === 0 && conditions.length === 0,
    currentBuyability: 'not_verified',
    quotedShippingScenario,
    observedOn: offer.observedOn ?? null, sourceUrl: offer.sourceUrl ?? null,
    quoteBasis: offer.quoteBasis ?? 'saved_source_snapshot',
    evidenceIds: [...(offer.evidenceIds ?? [])],
    comparisonScope: 'Saved offer and user-entered scenario only; bundle cost includes promos/accessories and does not predict pull value.',
  });
}

/** Reader-edited prices get their own provenance, not the saved seller's label. */
export function createCustomEtbOffer(input) {
  if (!input || typeof input !== 'object') throw new TypeError('Custom quote inputs are required.');
  const offer = {
    id: 'reader-entered-quote', label: 'Your entered quote', quoteBasis: 'user_entered_scenario',
    editionId: input.editionId, saleUnit: input.saleUnit, boxesPerSaleUnit: input.boxesPerSaleUnit,
    minSaleUnits: input.minSaleUnits, priceCents: input.priceCents,
    shipping: { kind: 'unknown', amountCents: null, quotedSaleUnits: null },
    availability: 'unknown', membershipRequired: input.membershipRequired,
    observedMaxSaleUnits: null, purchaseLimitBoxes: null,
    sourceUrl: null, observedOn: null, evidenceIds: [],
    note: 'Price, sale unit and minimum are reader inputs. Current stock, shipping and tax require separate confirmation.',
  };
  validateOffer(offer);
  return offer;
}

/** Return all results; never pick a universal cheapest offer from incomplete costs. */
export function compareEtbOffers(offers, request, adjustmentsByOffer = {}) {
  if (!Array.isArray(offers)) throw new TypeError('offers must be an array.');
  return offers.map(offer => calculateEtbOffer(offer, request, adjustmentsByOffer[offer.id] ?? {}));
}

export function formatEtbUsd(cents) {
  if (cents === null || cents === undefined) return 'Not established';
  if (!Number.isSafeInteger(cents)) throw new TypeError('formatEtbUsd requires an integer number of cents.');
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(cents / 100);
}

/** Convert a form's dollar input without converting a blank into zero. */
export function etbDollarsToCents(value) {
  if (value === null || value === undefined || String(value).trim() === '') return null;
  const text = String(value).trim();
  if (!/^\d+(?:\.\d{1,2})?$/.test(text)) throw new TypeError('Enter a nonnegative dollar amount with no more than two decimal places.');
  const [whole, fraction = ''] = text.split('.');
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
  return integer(cents, 'dollar amount');
}
