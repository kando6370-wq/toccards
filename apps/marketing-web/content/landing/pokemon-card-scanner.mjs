export default {
  "slug": "pokemon-card-scanner",
  "group": "tcg",
  "linkLabel": "Pokemon card scanner",
  "title": "Pokemon Card Scanner: Check Pokemon Card Values | Card AI",
  "description": "Scan Pokemon cards to find matching set and card records, confirm the printing, then check raw and graded market values and track your collection.",
  "eyebrow": "Pokemon",
  "h1": "Pokemon card scanner and value checker.",
  "lede": "Point your camera at a Pokemon card. Card AI suggests likely catalog matches for you to confirm before checking the price.",
  "proof": {
    "kind": "scan",
    "title": "Review the printing before checking its value.",
    "body": "Card AI suggests likely set and card-number records. Confirm edition, artwork, finish, and language, then inspect the selected card in the [card price checker](/card-price-checker)."
  },
  "cta": "Scan Pokemon cards, confirm the exact printing, and track raw or graded copies in one collection.",
  "sections": [
    {
      "h2": "Why the exact printing decides the price",
      "body": "Two Pokemon cards can show the same artwork and the same name and be worth very different amounts. What separates them is the printing: the set, the card number, whether it is a first edition or unlimited run, and whether the card is holo, reverse holo, or non-holo.\n\nCard AI compares the photo with its catalog and suggests likely records with the set and card number. Review the result and confirm the edition, variant and finish before using that printing's market price."
    },
    {
      "h2": "Raw and graded Pokemon cards are priced separately",
      "body": "Grading changes what a Pokemon card is worth, sometimes by an order of magnitude. Card AI keeps the two apart instead of averaging them.\n\n- Raw copies are tracked by condition, so a near-mint card and a lightly played one are not treated as the same asset.\n- Graded copies are recorded with the grading company and grade, covering PSA, BGS, CGC and SGC.\n- The same card can sit in your collection more than once, as a raw copy and a PSA 10, each with its own value.\n\nYou record the grade from the slab yourself. Card AI does not predict what a raw card would grade."
    },
    {
      "h2": "Scan a stack, not one card at a time",
      "body": "Most Pokemon collections are not one rare card, they are boxes of bulk with a few keepers inside. Bulk scanning lets you work through a stack in a single session and add everything to your collection together, which is the difference between cataloging a shoebox in an evening and never starting."
    },
    {
      "h2": "Watch your Pokemon collection value move",
      "body": "Once cards are in your collection they behave like a portfolio. Card AI totals what you own, keeps price history on individual cards, and updates as the market moves, so you can see whether a set is appreciating before you decide to sell or keep buying."
    }
  ],
  "faq": [
    {
      "q": "Can Card AI tell a first edition Pokemon card from an unlimited print?",
      "a": "The scan suggests likely catalog records, but you should check the edition marking and confirm the matching record and finish in Review because they materially change the value."
    },
    {
      "q": "Does the Pokemon card scanner work on Japanese cards?",
      "a": "Language is tracked as part of a card record, so Japanese and English copies of the same card are stored and priced as separate entries in your collection."
    },
    {
      "q": "What is my Pokemon card worth?",
      "a": "Select the matching catalog record, confirm its edition and finish, and choose a raw condition or existing slab grade. Card AI then shows the relevant market price and available price history."
    },
    {
      "q": "Is there a Pokemon card price checker built in?",
      "a": "Yes. Scanning is the fast route, but the Pokemon card price checker also searches the catalog by name, set or number. Open a matching record to check its current market price, then add it to the same collection tracker if you own it."
    },
    {
      "q": "Is the Pokemon card value scanner the same as the price checker?",
      "a": "They reach the same record. The Pokemon card price scanner reads the card from a photo; the checker finds it by search. Either way you land on the same printing with the same market price and history."
    }
  ],
  "related": [
    "mtg-card-scanner",
    "card-price-checker"
  ]
};
