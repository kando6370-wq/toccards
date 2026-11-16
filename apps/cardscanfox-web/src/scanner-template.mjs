const escape = value => String(value).replace(/[&<>"']/g, char => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[char]));
export function renderWebScanner({mode = 'pokemon', query = '', sportsGames = [], tcgGames = [], selectedGame = ''} = {}) {
 if (!['pokemon', 'sports', 'tcg'].includes(mode)) throw new TypeError('Unknown scanner mode.');
 const pokemon = mode === 'pokemon', tcg = mode === 'tcg';
 const path = pokemon ? '/pokemon-card-scanner' : tcg ? '/card-identifier' : '/sports-card-scanner';
 const subject = pokemon ? 'Pokémon card' : tcg ? 'trading card' : 'sports card';
 const selectorId = tcg ? 'web-scanner-game' : 'web-scanner-sport';
 const gameSelect = pokemon ? '' : `<label for="${selectorId}">${tcg ? 'Game' : 'Sport'}</label><select id="${selectorId}" name="game" required><option value="" disabled${selectedGame ? '' : ' selected'}>Choose a ${tcg ? 'game' : 'sport'}</option>${(tcg ? tcgGames : sportsGames).map(game => `<option value="${escape(game.slug)}"${game.slug === selectedGame ? ' selected' : ''}>${escape(game.name)}</option>`).join('')}</select>`;
 return `<section class="web-scanner" data-web-scanner data-mode="${mode}" aria-labelledby="web-scanner-title">
  <div class="web-scanner-intro"><h2 id="web-scanner-title">Identify your ${subject} here.</h2><p>Choose one clear photo of the card front. Crop it to the card edges before selecting it, and keep the whole card in view.</p></div>
  <form class="web-scanner-form" data-scan-form>
   <div class="web-scanner-upload">
    <label for="web-scanner-photo">Card photo</label>
    <input id="web-scanner-photo" data-scan-file type="file" accept="image/jpeg,image/png,image/webp" aria-describedby="web-scanner-file-help">
    <button class="btn btn-outline" data-open-camera type="button">Take a photo</button>
    <input data-camera-file type="file" accept="image/jpeg,image/png,image/webp" capture="environment" hidden>
    <p class="small-note" id="web-scanner-file-help">JPEG, PNG or WebP · Up to 20 MB and 24 megapixels. Photograph one card at a time.</p>
   </div>
   <figure class="web-scanner-preview" data-scan-preview hidden><img data-preview-image alt="Your selected card photo"><figcaption data-preview-caption></figcaption></figure>
   <div class="web-scanner-actions"><button class="btn btn-primary" data-scan-submit type="submit" disabled>Identify card</button><button class="btn btn-outline" data-scan-reset type="button" hidden>Clear photo</button></div>
   <p class="small-note">The first scan loads about 26 MB of scanner files. We process the photo in your browser and send its image vector for matching.</p>
   <p class="web-scanner-status" data-scan-status role="status" aria-live="polite" aria-atomic="true">Choose a card photo to start.</p>
   <p class="web-scanner-error" data-scan-error role="alert" hidden></p>
  </form>
  <section class="web-scanner-results" data-scan-results aria-labelledby="web-scanner-results-title" hidden><h3 id="web-scanner-results-title">Compare the matching cards.</h3><p>Check the artwork, full card number, set and finish against your copy. These are catalog candidates. For a separate visible-condition estimate, use <a href="/ai-card-grading">AI pregrading</a>; catalog matching does not authenticate or grade a card.</p><div class="web-scanner-candidates" data-scan-candidates></div></section>
  <div class="web-scanner-lookup"><h3>Search by name or number.</h3><p>Have the card number, or need another way to find it? Use text lookup.</p><form method="get" action="${path}" class="web-scanner-text-form">${gameSelect}<label for="web-scanner-query">Card name, set or number</label><input id="web-scanner-query" name="q" type="search" maxlength="128" value="${escape(query)}" placeholder="${pokemon ? 'Charizard 199/165' : tcg ? 'Card name, set or collector number' : 'Player, set or card number'}" required><button class="btn btn-outline" type="submit">Find cards</button></form><div data-text-results><!-- SCANNER_TEXT_RESULTS --></div></div>
  <noscript><p>Photo scanning needs JavaScript. You can use the text lookup above.</p></noscript>
 </section><script type="module" src="/assets/web-scanner.js"></script>`;
}
