const escapeHtml = (value) => String(value)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function renderPrice(record) {
  const price = Number.isFinite(record.priceUsd) && record.priceUsd >= 0
    ? `$${record.priceUsd.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
    : 'Price unavailable';
  const date = record.priceAsOf ? ` · <time datetime="${escapeHtml(record.priceAsOf)}">${escapeHtml(record.priceAsOf)}</time>` : '';
  return `<li><span>${escapeHtml(record.printing)}</span> · <strong>${price}</strong>${date}</li>`;
}

export function renderCardList(snapshot) {
  const rows = snapshot.cards.map((card) => {
    const priced = card.records.some((record) => Number.isFinite(record.priceUsd) && record.priceUsd >= 0);
    const prices = card.records.length
      ? `<ul class="card-list-prices">${card.records.map(renderPrice).join('')}</ul>`
      : '<span>No matching catalog record in this snapshot.</span>';
    const search = `${card.number} ${card.name} ${card.records.map((record) => record.printing).join(' ')}`;
    return `<tr id="card-${escapeHtml(card.number.split('/')[0])}" data-card-row data-search="${escapeHtml(search)}" data-priced="${priced}"><th scope="row">${escapeHtml(card.number)}</th><td>${escapeHtml(card.name)}</td><td>${prices}</td></tr>`;
  }).join('\n');

  return `<section class="card-list" id="card-list" data-card-list>
            <h2>Browse the ${escapeHtml(snapshot.setName)} card list</h2>
            <p>${snapshot.cards.length} numbered cards from the <a href="${escapeHtml(snapshot.checklistUrl)}">official English checklist</a>. Card names and numbers follow that checklist; different finishes can have separate price samples.</p>
            <p>Prices are a Card AI catalog snapshot retrieved ${escapeHtml(snapshot.observedAt)}, in USD. Each price shows its own observation date. These samples do not specify a raw condition or slab grade. Use the app to review the confirmed record and any available condition or grade-specific prices.</p>
            <form class="card-list-controls" role="search" hidden>
              <div><label for="card-list-query">Find a card by name or number</label><input id="card-list-query" type="search" placeholder="Name or collector number" autocomplete="off" aria-controls="card-list-table"></div>
              <div><label for="card-list-price">Price coverage</label><select id="card-list-price" aria-controls="card-list-table"><option value="all">All cards</option><option value="priced">With a price sample</option><option value="missing">Without a price sample</option></select></div>
              <button type="reset">Clear filters</button>
            </form>
            <p class="card-list-count" data-card-count aria-live="polite">${snapshot.cards.length} cards shown.</p>
            <p data-card-empty hidden>No cards match these filters. Try a name or collector number, or clear the filters.</p>
            <div class="content-table-wrap"><table id="card-list-table"><caption>${escapeHtml(snapshot.setName)} · English · ${escapeHtml(snapshot.setCode)} · dated reference prices</caption><thead><tr><th scope="col">Card number</th><th scope="col">Card</th><th scope="col">Printing · published USD sample · date</th></tr></thead><tbody>${rows}</tbody></table></div>
            <p>Missing prices stay missing. Code cards, boxes, packs and unnumbered promos are not part of this numbered checklist. These reference values are not offers or guaranteed sale prices. Check the <a href="${escapeHtml(snapshot.galleryUrl)}">official card gallery</a> against the artwork on your copy.</p>
          </section>`;
}
