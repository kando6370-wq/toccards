export default function homeTemplate({ appStoreUrl, heroCards, printing, priceBadge, catalogCards, topics, stories, icon }) {
  return `<section id="homeView">
  <section class="home-hero" aria-labelledby="hero-title">
    <div class="hero-canvas">
      <div class="hero-copy">
        <h1 id="hero-title">Scan Cards.<br>Track Your Collection.</h1>
        <p class="hero-lede">Identify TCG and sports cards, check prices, and manage your collection with CardScanFox.</p>
        <div class="hero-actions">
          <a class="btn btn-primary" href="${appStoreUrl}" target="_blank" rel="noopener noreferrer">App Store</a>
          <a class="btn btn-outline" href="/download">Android is coming soon</a>
        </div>
        <div class="hero-lookup"><a class="text-link" href="/card-identifier">Scan a photo online ${icon('arrow')}</a><a class="text-link" href="/cards">Browse the catalog ${icon('arrow')}</a></div>
      </div>
      <div class="hero-stage" role="group" aria-label="Explore featured card printings">
        <div class="hero-glow" aria-hidden="true"></div>
        <div class="hero-disc" aria-hidden="true"></div>
        ${heroCards}
        <img class="hero-annotation annotation-scan" src="/assets/hero/annotation-scan.png" alt="" aria-hidden="true">
        <img class="hero-annotation annotation-rays" src="/assets/hero/annotation-rays.png" alt="" aria-hidden="true">
        <img class="hero-annotation annotation-exact" src="/assets/hero/annotation-exact.png" alt="" aria-hidden="true">
        ${printing}
        ${priceBadge}
        <img class="hero-annotation annotation-price" src="/assets/hero/annotation-price.png" alt="" aria-hidden="true">
      </div>
    </div>
  </section>
  <section class="home-library" id="catalog" aria-labelledby="catalog-title">
    <div class="wrap">
      <div class="home-section-heading">
        <h2 id="catalog-title">Card Prices</h2>
        <div><p>Look up TCG and sports cards by name, set or number. Match the printing before comparing prices.</p><a class="text-link" href="/cards">Browse the catalog ${icon('arrow')}</a></div>
      </div>
      <div class="card-grid home-card-preview">${catalogCards}</div>
      <p class="home-catalog-note">Collect Pokémon TCG? <a href="/games/pokemon">Check Pokémon card prices</a> by set and collector number.</p>
    </div>
  </section>
  ${topics}
  <section class="fox-workbench" aria-labelledby="workbenchTitle">
    <div class="wrap">
      <div class="home-section-heading"><h2 id="workbenchTitle">App Features</h2><p>Scan cards, follow prices, and manage what you own in the CardScanFox app.</p></div>
      <div class="fox-workbench-grid">
        <div class="fox-feature-tabs" role="tablist" aria-label="Explore app features" aria-orientation="vertical">
          <button type="button" class="fox-feature-tab active" id="feature-tab-scan" data-feature-tab="scan" role="tab" aria-selected="true" aria-controls="feature-panel-scan"><span class="feature-tab-title">Scan &amp; confirm ${icon('arrow')}</span><span>Start from a photo or a catalog search.</span></button>
          <button type="button" class="fox-feature-tab" id="feature-tab-price" data-feature-tab="price" role="tab" aria-selected="false" aria-controls="feature-panel-price" tabindex="-1"><span class="feature-tab-title">Understand the price ${icon('arrow')}</span><span>Check the reference for the copy you own.</span></button>
          <button type="button" class="fox-feature-tab" id="feature-tab-collect" data-feature-tab="collect" role="tab" aria-selected="false" aria-controls="feature-panel-collect" tabindex="-1"><span class="feature-tab-title">Track your collection ${icon('arrow')}</span><span>Organize holdings, folders and Wishlist.</span></button>
        </div>
        <div class="fox-feature-panels">
          <section class="fox-feature-panel" id="feature-panel-scan" role="tabpanel" aria-labelledby="feature-tab-scan"><div class="fox-app-illustration"><img src="/assets/scan.webp" alt="Card scan and match results in the app" width="759" height="350" loading="lazy"></div><div class="fox-feature-body"><h3>Find the correct printing.</h3><p>Compare the set, collector number, finish and language with the card in your hand.</p></div></section>
          <section class="fox-feature-panel" id="feature-panel-price" role="tabpanel" aria-labelledby="feature-tab-price" hidden><div class="fox-app-illustration"><img src="/assets/price-view.webp" alt="Reference card price and history in the app" width="759" height="350" loading="lazy"></div><div class="fox-feature-body"><h3>Check a dated price reference.</h3><p>Compare the published amounts for the printing and condition you selected.</p></div></section>
          <section class="fox-feature-panel" id="feature-panel-collect" role="tabpanel" aria-labelledby="feature-tab-collect" hidden><div class="fox-app-illustration"><img src="/assets/portfolio.webp" alt="Portfolio value and collection trends in the app" width="759" height="350" loading="lazy"></div><div class="fox-feature-body"><h3>Know what you own.</h3><p>Record quantities, organize your holdings into folders, and save cards you want in your Wishlist.</p></div></section>
        </div>
      </div>
      <p class="fox-illustration-note">App screenshots use example values.</p>
    </div>
  </section>
  <section class="home-workflow" id="home-workflow">
    <div class="wrap fox-process">
      <div class="fox-process-intro"><h2>How It Works</h2><p>Follow the same steps for each card so your holdings stay accurate as your collection grows.</p></div>
      <ol class="fox-process-steps"><li><span>1</span><h3>Find</h3><p>Scan a photo or search by name, set or number.</p></li><li><span>2</span><h3>Confirm</h3><p>Check the printing, language and finish.</p></li><li><span>3</span><h3>Record</h3><p>Add quantity, raw condition or the grade on your slab.</p></li><li><span>4</span><h3>Collect</h3><p>Organize holdings and follow available price changes.</p></li></ol>
    </div>
  </section>
  <section class="home-boundary">
    <div class="wrap fox-app-boundary">
      <div class="fox-boundary-intro"><h2>Website and App</h2><p>Research cards online. Manage your collection in the app.</p><a class="text-link" href="/help">Read the data &amp; coverage notes ${icon('arrow')}</a></div>
      <div class="fox-boundary-table"><div class="boundary-row boundary-table-head"><span>Your next task</span><span>Website</span><span>App</span></div><div class="boundary-row"><span>Look up cards and reference prices</span><span aria-label="Available">${icon('check')}</span><span aria-label="Available">${icon('check')}</span></div><div class="boundary-row"><span>Identify a physical card from a photo</span><a href="/card-identifier">Web tool</a><span aria-label="Available">${icon('check')}</span></div><div class="boundary-row"><span>Record holdings, condition and quantity</span><span class="boundary-app-only">In the app</span><span aria-label="Available">${icon('check')}</span></div><div class="boundary-row"><span>Manage Portfolio, folders and Wishlist</span><span class="boundary-app-only">In the app</span><span aria-label="Available">${icon('check')}</span></div></div>
    </div>
  </section>
  <section class="wrap home-journal" id="journal">
    <div class="home-section-heading"><h2>Collecting Guides</h2><div><p>Compare printings, understand prices and find the right scanner for your collection.</p><a class="text-link" href="/blog/">Visit the journal ${icon('arrow')}</a></div></div>
    <div class="blog-posts">${stories}</div>
  </section>
  <section class="home-questions">
    <div class="wrap fox-questions"><div><h2>Frequently Asked Questions</h2><a class="text-link" href="/help">All questions ${icon('arrow')}</a></div><div class="faq-list"><details><summary>What kinds of cards can I look up? ${icon('chevron')}</summary><p>Browse supported TCG and sports-card records. Catalog coverage and published prices vary by game and printing.</p></details><details><summary>Do I need to scan a card to find a price? ${icon('chevron')}</summary><p>No. Search by name, set or card number. Confirm the printing and the copy’s condition or existing grade before using an available price reference.</p></details><details><summary>Why can a card have no price? ${icon('chevron')}</summary><p>A catalog record can exist without a matching published price. Missing coverage does not mean zero value. A different printing’s amount is not substituted.</p></details><details><summary>What does saving a card on this website do? ${icon('chevron')}</summary><p>Saved references stay in this browser. Portfolio, folders and Wishlist are managed in the app.</p></details></div></div>
  </section>
  <section class="home-download">
    <div class="wrap fox-final"><div><h2>Download CardScanFox</h2><p>Scan your cards and track what you own.</p><a class="btn btn-primary" href="/download">Choose your download ${icon('arrow')}</a></div><img class="fox-final-mark" src="/assets/cardscanfox-lime-mark.svg" alt="" width="116" height="116" loading="lazy"></div>
  </section>
</section>`;
}
