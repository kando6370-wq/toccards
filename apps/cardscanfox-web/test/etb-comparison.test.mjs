import assert from 'node:assert/strict';
import test from 'node:test';
import {
  ETB_SNAPSHOT_OFFERS,
  calculateEtbOffer,
  createCustomEtbOffer,
  etbDollarsToCents,
} from '../src/etb-comparison.mjs';

const offer = id => {
  const found = ETB_SNAPSHOT_OFFERS.find(item => item.id === id);
  assert.ok(found, `Missing dated offer: ${id}`);
  return found;
};
const oneBox = {desiredBoxes: 1, budgetCents: 10_000, editionId: 'regular', proMember: false};

test('a single-box quote keeps unknown checkout tax separate from its known delivered subtotal', () => {
  const result = calculateEtbOffer(offer('great-buys-single'), oneBox);
  assert.equal(result.actualBoxes, 1);
  assert.equal(result.extraBoxes, 0);
  assert.equal(result.knownBeforeTaxTotalCents, 8_498);
  assert.equal(result.shippingCents, 0);
  assert.equal(result.totalWithEnteredTaxCents, null);
  assert.equal(result.budgetHeadroomBeforeTaxCents, 1_502);
  assert.equal(result.budgetStatus, 'needs_shipping_or_tax');
  assert.equal(result.currentBuyability, 'not_verified');
});

test('a one-box goal still incurs the three-box minimum and does not invent multi-item shipping', () => {
  const result = calculateEtbOffer(offer('san-diego-min-three'), oneBox);
  assert.equal(result.actualBoxes, 3);
  assert.equal(result.extraBoxes, 2);
  assert.equal(result.goodsCents, 24_000);
  assert.equal(result.shippingCents, null);
  assert.equal(result.knownBeforeTaxTotalCents, null);
  assert.equal(result.totalWithEnteredTaxCents, null);
  assert.equal(result.budgetStatus, 'over_budget');
  assert.equal(result.quotedShippingScenario.beforeTaxTotalCents, 24_399);
  assert.ok(result.missingAmounts.includes('order_shipping'));
});

test('a confirmed whole-order shipping scenario is counted once and still leaves absent tax unknown', () => {
  const selected = offer('san-diego-min-three');
  const ignored = calculateEtbOffer(selected, oneBox, {shippingCents: 399});
  assert.equal(ignored.shippingCents, null);
  assert.ok(ignored.missingAmounts.includes('shipping_confirmation'));

  const result = calculateEtbOffer(selected, {...oneBox, budgetCents: 25_000}, {
    shippingCents: 399,
    shippingConfirmedForOrder: true,
  });
  assert.equal(result.goodsCents, 24_000);
  assert.equal(result.shippingCents, 399);
  assert.equal(result.knownBeforeTaxTotalCents, 24_399);
  assert.equal(result.perBoxBeforeTax.roundedCents, 8_133);
  assert.equal(result.totalWithEnteredTaxCents, null);
  assert.equal(result.budgetStatus, 'needs_shipping_or_tax');
});

test('case arithmetic exposes the whole cash commitment instead of selling a fractional case', () => {
  const result = calculateEtbOffer(offer('xaobx-ten-box-case'), oneBox);
  assert.equal(result.saleUnits, 1);
  assert.equal(result.actualBoxes, 10);
  assert.equal(result.extraBoxes, 9);
  assert.equal(result.totalPacks, 90);
  assert.equal(result.knownBeforeTaxTotalCents, 71_696);
  assert.equal(result.perBoxBeforeTax.roundedCents, 7_170);
  assert.equal(result.perPackBeforeTax.roundedCents, 797);
  assert.equal(result.budgetStatus, 'over_budget');
});

test('additional cases do not reuse the one-case shipping quote or exceed its saved seller quantity silently', () => {
  const result = calculateEtbOffer(offer('xaobx-ten-box-case'), {...oneBox, desiredBoxes: 11, budgetCents: 200_000});
  assert.equal(result.saleUnits, 2);
  assert.equal(result.actualBoxes, 20);
  assert.equal(result.goodsCents, 142_392);
  assert.equal(result.shippingCents, null);
  assert.equal(result.knownBeforeTaxTotalCents, null);
  assert.ok(result.blockers.includes('exceeds_observed_seller_quantity'));
});

test('the unavailable Center reference retains its edition and cannot become a buyable low-price result', () => {
  const selected = offer('pokemon-center-official');
  const result = calculateEtbOffer(selected, {...oneBox, editionId: 'pokemon-center'});
  assert.equal(result.packsPerBox, 11);
  assert.equal(result.totalPromos, 2);
  assert.equal(result.totalCenterLogoPromos, 1);
  assert.equal(result.snapshotEligible, false);
  assert.ok(result.blockers.includes('unavailable_in_saved_snapshot'));
  assert.equal(result.currentBuyability, 'not_verified');
  const aboveLimit = calculateEtbOffer(selected, {...oneBox, editionId: 'pokemon-center', desiredBoxes: 3});
  assert.ok(aboveLimit.blockers.includes('exceeds_observed_purchase_limit'));
});

test('Pro pricing requires eligibility and does not establish location stock', () => {
  const selected = offer('gamestop-pro');
  const nonMember = calculateEtbOffer(selected, oneBox);
  assert.equal(nonMember.snapshotEligible, false);
  assert.ok(nonMember.blockers.includes('pro_membership_required'));
  const unknownMember = calculateEtbOffer(selected, {...oneBox, proMember: null});
  assert.ok(unknownMember.conditions.includes('pro_membership_not_confirmed'));
  const member = calculateEtbOffer(selected, {...oneBox, proMember: true});
  assert.ok(member.conditions.includes('location_and_stock_check_required'));
  assert.equal(member.shippingCents, null);
  assert.equal(member.currentBuyability, 'not_verified');
});

test('explicit zero costs and a zero budget retain their meanings', () => {
  const result = calculateEtbOffer(offer('gamestop-standard'), oneBox, {
    shippingCents: 0,
    shippingConfirmedForOrder: true,
    taxCents: 0,
  });
  assert.equal(result.knownBeforeTaxTotalCents, 9_999);
  assert.equal(result.totalWithEnteredTaxCents, 9_999);
  assert.equal(result.budgetStatus, 'within_entered_budget');
  assert.equal(result.currentBuyability, 'not_verified');

  const noBudget = calculateEtbOffer(offer('great-buys-single'), {...oneBox, budgetCents: 0});
  assert.equal(noBudget.budgetCents, 0);
  assert.equal(noBudget.budgetStatus, 'over_budget');
});

test('invalid desired quantities fail instead of becoming a default one-box or zero-dollar result', () => {
  for (const desiredBoxes of [0, 1.5, '1', undefined]) {
    assert.throws(() => calculateEtbOffer(offer('great-buys-single'), {desiredBoxes}), TypeError);
  }
});

test('reader-entered quotes use their own units, membership conditions and provenance', () => {
  const custom = createCustomEtbOffer({
    editionId: 'regular', saleUnit: 'case', boxesPerSaleUnit: 10,
    minSaleUnits: 1, priceCents: 60_000, membershipRequired: false,
  });
  const result = calculateEtbOffer(custom, {...oneBox, budgetCents: 70_000}, {
    shippingCents: 1_000, shippingConfirmedForOrder: true, taxCents: 0,
  });
  assert.equal(result.actualBoxes, 10);
  assert.equal(result.knownBeforeTaxTotalCents, 61_000);
  assert.equal(result.sourceUrl, null);
  assert.equal(result.observedOn, null);
  assert.deepEqual(result.evidenceIds, []);
  assert.equal(result.quoteBasis, 'user_entered_scenario');
  assert.equal(result.currentBuyability, 'not_verified');

  const memberOnly = createCustomEtbOffer({
    editionId: 'regular', saleUnit: 'box', boxesPerSaleUnit: 1,
    minSaleUnits: 1, priceCents: 9_000, membershipRequired: true,
  });
  assert.ok(calculateEtbOffer(memberOnly, oneBox).blockers.includes('pro_membership_required'));
});

test('money parsing preserves blanks and exact cents while rejecting extra precision', () => {
  assert.equal(etbDollarsToCents(''), null);
  assert.equal(etbDollarsToCents('  '), null);
  assert.equal(etbDollarsToCents('0'), 0);
  assert.equal(etbDollarsToCents('1.05'), 105);
  assert.throws(() => etbDollarsToCents('1.005'), TypeError);
  assert.throws(() => etbDollarsToCents('-1'), TypeError);
});
