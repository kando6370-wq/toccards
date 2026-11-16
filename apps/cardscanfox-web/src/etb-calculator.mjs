import {ETB_SNAPSHOT_DATE, ETB_SNAPSHOT_OFFERS, calculateEtbOffer, createCustomEtbOffer, formatEtbUsd, etbDollarsToCents} from './etb-comparison.mjs';

const conditionText = {
 unavailable_in_saved_snapshot: 'The product was unavailable in the saved listing.',
 different_selected_edition: 'This quote is for a different edition from the one selected.',
 pro_membership_required: 'This price requires Pro membership.',
 pro_membership_not_confirmed: 'Pro membership has not been confirmed.',
 location_and_stock_check_required: 'Check the selected condition, delivery location and stock.',
 current_stock_not_checked: 'This is a dated quote. Check current stock with the seller.',
 availability_not_established: 'Availability has not been established.',
 exceeds_observed_purchase_limit: 'The order exceeds the purchase limit shown in the saved listing.',
 exceeds_observed_seller_quantity: 'The order exceeds the quantity shown by that seller in the saved listing.',
};
const budgetText = {
 not_entered: 'No budget entered.',
 over_budget: 'Known costs already exceed your budget.',
 within_entered_budget: 'Within the entered cost scenario. Confirm checkout costs and stock.',
 needs_shipping_or_tax: 'Known costs fit your budget; shipping or tax is still missing.',
};

function inputMessage(error) {
 const message = error.message ?? '';
 if (message === 'Choose a specific edition for your own quote.') return message;
 if (/desiredBoxes|minSaleUnits|boxesPerSaleUnit|one box/.test(message)) return 'Enter positive whole numbers for boxes, sale-unit quantity and the minimum order. A one-box sale unit must contain one box.';
 if (/cents|dollar|decimal/.test(message)) return 'Enter nonnegative dollar amounts with up to two decimal places. Leave unknown fees blank.';
 return 'Check the quote edition, sale unit, quantity and amounts, then calculate again.';
}

export function initEtbCalculator(root = document) {
 const form = root.querySelector('#etb-calc-form');
 if (!form || form.dataset.etbInitialized === 'true') return;
 const field = id => form.querySelector('#' + id);
 const section = form.closest('.etb-calculator');
 const error = section.querySelector('#etb-calc-error');
 const output = section.querySelector('#etb-calc-result');
 const offerSelect = field('etb-offer');
 const ownerDocument = form.ownerDocument;
 const date = new Intl.DateTimeFormat('en-US', {day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC'}).format(new Date(ETB_SNAPSHOT_DATE + 'T12:00:00Z'));
 const element = (tag, text) => {const node = ownerDocument.createElement(tag); node.textContent = text; return node;};
 const money = cents => cents === null ? 'Not established' : formatEtbUsd(cents);
 const ratio = value => value ? money(value.roundedCents) : 'Not established';

 function renderCost() {
  error.hidden = true;
  try {
   const custom = offerSelect.value === 'custom';
   const customFields = field('etb-custom-fields');
   customFields.hidden = !custom;
   for (const control of customFields.querySelectorAll('input, select')) control.disabled = !custom;
   const editionId = field('etb-edition').value;
   if (custom && editionId === 'any') throw new TypeError('Choose a specific edition for your own quote.');
   const offer = custom ? createCustomEtbOffer({editionId, saleUnit: field('etb-unit').value,
    boxesPerSaleUnit: Number(field('etb-boxes-per-unit').value), minSaleUnits: Number(field('etb-minimum').value),
    priceCents: etbDollarsToCents(field('etb-price').value), membershipRequired: field('etb-custom-pro').checked})
    : ETB_SNAPSHOT_OFFERS.find(item => item.id === offerSelect.value);
   const request = {desiredBoxes: Number(field('etb-desired').value), budgetCents: etbDollarsToCents(field('etb-budget').value), editionId,
    proMember: field('etb-pro').value === 'unknown' ? null : field('etb-pro').value === 'yes'};
   const result = calculateEtbOffer(offer, request, {shippingCents: etbDollarsToCents(field('etb-shipping').value),
    shippingConfirmedForOrder: field('etb-shipping-confirmed').checked, taxCents: etbDollarsToCents(field('etb-tax').value)});

   output.replaceChildren();
   output.dataset.offerId = offer.id;
   output.dataset.actualBoxes = String(result.actualBoxes);
   output.dataset.beforeTax = String(result.knownBeforeTaxTotalCents);
   output.dataset.budgetStatus = result.budgetStatus;
   output.append(element('h5', custom ? 'Your entered quote' : offer.label + ' · checked ' + date));
   if (result.blockers.length) {
    const blocker = element('p', 'Quote conditions are not met: ' + result.blockers.map(key => conditionText[key] ?? key).join(' '));
    blocker.className = 'etb-calc-blocker'; output.append(blocker);
   }
   const budget = element('p', budgetText[result.budgetStatus]);
   budget.className = 'etb-budget-status'; output.append(budget);
   const values = [
    ['Boxes wanted', result.desiredBoxes], ['Actual boxes in the minimum order', result.actualBoxes], ['Extra boxes above your goal', result.extraBoxes],
    ['Goods subtotal', money(result.goodsCents)], ['Order shipping applied', money(result.shippingCents)],
    ['Order amount before tax', money(result.knownBeforeTaxTotalCents)], ['Cost per ETB before tax', ratio(result.perBoxBeforeTax)],
    ['Bundle cost per included pack', ratio(result.perPackBeforeTax)], ['Entered checkout tax', money(result.enteredTaxCents)],
    ['Total with entered tax', money(result.totalWithEnteredTaxCents)],
   ];
   const amounts = ownerDocument.createElement('dl');
   for (const [label, value] of values) amounts.append(element('dt', label), element('dd', String(value)));
   output.append(amounts);
   if (result.budgetHeadroomBeforeTaxCents !== null && result.budgetHeadroomBeforeTaxCents >= 0) {
    output.append(element('p', 'Budget remaining after the known before-tax amount: ' + money(result.budgetHeadroomBeforeTaxCents) + '. Tax and other checkout charges use this remaining amount.'));
   }
   const notes = [...result.conditions].map(key => conditionText[key] ?? key);
   if (result.shippingCents === null) notes.unshift('Order shipping is unknown. The goods subtotal alone does not establish a delivered total.');
   if (result.enteredTaxCents === null) notes.push('Tax has not been entered. The before-tax amount is not a final checkout total.');
   if (result.missingAmounts.includes('shipping_confirmation')) notes.push('Your entered shipping amount has not been confirmed for this whole order and was not applied.');
   if (notes.length) {const list = ownerDocument.createElement('ul'); for (const note of notes) list.append(element('li', note)); output.append(list);}
   if (result.quotedShippingScenario) {
    output.append(element('p', 'Conditional example: if the seller confirms that $3.99 covers this whole order, its before-tax amount is ' + money(result.quotedShippingScenario.beforeTaxTotalCents) + '. That shipping scope was not checked.'));
   }
   const packNote = element('p', 'The per-pack figure divides the full ETB bundle cost, including promos and accessories. It does not predict pull value.');
   packNote.className = 'etb-help'; output.append(packNote);
   if (result.sourceUrl) {
    const source = element('a', 'View the source listing'); source.href = result.sourceUrl; source.target = '_blank'; source.rel = 'noopener noreferrer'; output.append(source);
   }
   if (custom) output.append(element('p', 'Source: your inputs. This result does not carry the saved seller’s date, quantity or stock status.'));
  } catch (cause) {
   error.textContent = inputMessage(cause);
   error.hidden = false;
   output.replaceChildren();
   for (const key of ['offerId', 'actualBoxes', 'beforeTax', 'budgetStatus']) delete output.dataset[key];
  }
 }

 form.addEventListener('submit', event => {event.preventDefault(); renderCost();});
 offerSelect.addEventListener('change', () => {
  const offer = ETB_SNAPSHOT_OFFERS.find(item => item.id === offerSelect.value);
  if (offer) field('etb-edition').value = offer.editionId;
  field('etb-shipping').value = '';
  field('etb-shipping-confirmed').checked = false;
  renderCost();
 });
 field('etb-unit').addEventListener('change', () => {
  field('etb-boxes-per-unit').value = field('etb-unit').value === 'box' ? '1' : '';
  field('etb-shipping-confirmed').checked = false;
 });
 for (const id of ['etb-desired', 'etb-boxes-per-unit', 'etb-minimum', 'etb-unit', 'etb-edition']) {
  field(id).addEventListener('input', () => {field('etb-shipping-confirmed').checked = false;});
 }
 form.dataset.etbInitialized = 'true';
 form.querySelector('[data-etb-controls]').disabled = false;
 renderCost();
 return {renderCost};
}

if (typeof document !== 'undefined') initEtbCalculator(document);
