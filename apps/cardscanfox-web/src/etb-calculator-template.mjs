import {ETB_SNAPSHOT_DATE, ETB_SNAPSHOT_OFFERS} from './etb-comparison.mjs';

const escape = value => String(value).replace(/[&<>"']/g, char => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[char]));

export function renderEtbCalculator() {
 const date = new Intl.DateTimeFormat('en-US', {day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC'}).format(new Date(ETB_SNAPSHOT_DATE + 'T12:00:00Z'));
 const quotes = ETB_SNAPSHOT_OFFERS.map(offer => `<option value="${escape(offer.id)}">${escape(offer.label)}</option>`).join('');
 return `<link rel="stylesheet" href="/assets/etb-calculator.css">
 <section class="etb-calculator" id="etb-cost-calculator" aria-labelledby="etb-calc-title">
  <header class="etb-calculator-heading">
   <p class="etb-calculator-label">Quantity &amp; budget</p>
   <h4 id="etb-calc-title">Calculate the whole ETB order.</h4>
   <p>Use this free, no-sign-in calculator to compare a Delta Reign ETB quote with your required number of boxes and whole-order budget. It shows minimum purchase quantities, extra boxes and known costs.</p>
   <p class="etb-help" id="etb-snapshot-help">Saved examples were checked ${escape(date)}. They are dated quotes, not a live stock feed. You can also enter your own quote.</p>
  </header>
  <form id="etb-calc-form" aria-labelledby="etb-calc-title" aria-describedby="etb-snapshot-help">
   <fieldset class="etb-controls" data-etb-controls disabled>
    <legend class="sr-only">ETB quote and order details</legend>
    <div class="etb-fields">
     <div><label for="etb-offer">Quote</label><select id="etb-offer">${quotes}<option value="custom">Enter my own quote</option></select></div>
     <div><label for="etb-edition">Edition wanted</label><select id="etb-edition"><option value="regular">Regular ETB · 9 packs, 1 promo</option><option value="pokemon-center">Pokémon Center · 11 packs, 2 promos</option><option value="any">Either edition; calculate the selected quote</option></select></div>
     <div><label for="etb-desired">Boxes wanted</label><input id="etb-desired" type="number" min="1" step="1" value="1" required aria-describedby="etb-quantity-help"></div>
     <div><label for="etb-budget">Whole-order budget (USD, optional)</label><input id="etb-budget" type="text" inputmode="decimal" value="100.00" placeholder="100.00" aria-describedby="etb-money-help"></div>
    </div>
    <p class="etb-help" id="etb-quantity-help">The order rounds up to whole boxes or cases and the seller's minimum. Extra boxes are shown separately.</p>
    <p class="etb-help" id="etb-money-help">Enter dollar amounts with up to two decimal places. Leave unknown fees blank.</p>
    <section class="etb-custom-fields" id="etb-custom-fields" aria-labelledby="etb-custom-title" hidden>
     <h5 id="etb-custom-title">Your quote</h5>
     <div class="etb-fields">
      <div><label for="etb-unit">Price is for</label><select id="etb-unit"><option value="box">One box</option><option value="case">One whole case</option></select></div>
      <div><label for="etb-boxes-per-unit">Boxes in that sale unit</label><input id="etb-boxes-per-unit" type="number" min="1" step="1" value="1" aria-describedby="etb-case-help"></div>
      <div><label for="etb-price">Price for that sale unit (USD)</label><input id="etb-price" type="text" inputmode="decimal" value="80.00"></div>
      <div><label for="etb-minimum">Minimum sale units per order</label><input id="etb-minimum" type="number" min="1" step="1" value="1" aria-describedby="etb-case-help"></div>
     </div>
     <p class="etb-help" id="etb-case-help">Use this seller's actual case quantity. A three-box minimum is 3 sale units when the price is per box.</p>
     <label class="etb-checkbox" for="etb-custom-pro"><input id="etb-custom-pro" type="checkbox"><span>This quote requires GameStop Pro</span></label>
     <p class="etb-help">Your quote uses your entered price and conditions. It keeps no saved seller date, source or inventory claim.</p>
    </section>
    <details class="etb-cost-details">
     <summary>Shipping, tax &amp; membership</summary>
     <div class="etb-fields">
      <div><label for="etb-shipping">Shipping for the whole computed order (USD)</label><input id="etb-shipping" type="text" inputmode="decimal" placeholder="Leave blank if unknown" aria-describedby="etb-shipping-help"></div>
      <div><label for="etb-tax">Checkout tax for this order (USD, optional)</label><input id="etb-tax" type="text" inputmode="decimal" placeholder="Leave blank if unknown" aria-describedby="etb-tax-help"></div>
      <div><label for="etb-pro">GameStop Pro membership</label><select id="etb-pro"><option value="unknown">Not confirmed</option><option value="yes">I have Pro</option><option value="no">I do not have Pro</option></select></div>
     </div>
     <label class="etb-checkbox" for="etb-shipping-confirmed"><input id="etb-shipping-confirmed" type="checkbox"><span>I confirmed this shipping amount covers the whole computed order</span></label>
     <p class="etb-help" id="etb-shipping-help">The $80 example displayed $3.99 shipping. Shipping for its required three-box order was not checked. Confirm the order amount before applying it.</p>
     <p class="etb-help" id="etb-tax-help">Blank tax stays unknown. Enter 0 only for an explicit zero-tax scenario.</p>
    </details>
    <button class="btn btn-primary" type="submit">Calculate order cost</button>
   </fieldset>
  </form>
  <p class="etb-calc-error" id="etb-calc-error" role="alert" tabindex="-1" hidden></p>
  <div class="etb-result" id="etb-calc-result" role="status" aria-live="polite" aria-atomic="true"><p>Choose a quote and calculate its order cost.</p></div>
  <noscript><p class="etb-help">The calculator needs JavaScript. The article's quote and minimum-order examples remain available above: the ten-box case requires $716.96 before tax, and the three-box minimum starts at a $240 goods subtotal before unconfirmed shipping and tax.</p></noscript>
 </section><script type="module" src="/assets/etb-calculator.js"></script>`;
}
