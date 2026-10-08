export default {
  "slug": "card-identifier",
  "group": "feature",
  "linkLabel": "Card identifier",
  "title": "Trading Card Identifier From a Photo | Card AI",
  "description": "Identify a trading card from a photo. AI card recognition suggests matching catalog records with the set and card number for you to review.",
  "eyebrow": "Identification",
  "h1": "Trading card identifier.",
  "lede": "Knowing the card name is not knowing the card. The identifier narrows the catalog; you confirm the printing that decides the price.",
  "proof": {
    "kind": "scan",
    "title": "See the candidate before you confirm the card.",
    "body": "A scan suggests catalog records with details such as set and card number. Review the candidate, confirm finish and language, then continue to the [card price checker](/card-price-checker)."
  },
  "cta": "Photograph a card, review the likely match, and save only the printing you confirm.",
  "sections": [
    {
      "h2": "Naming a card is the easy half",
      "body": "A card name alone is not enough, because the same name can cover printings that trade at very different prices.\n\nCard AI compares the photo with its catalog and suggests matching card records with the set and card number. You review those candidates, select the correct record, and confirm details such as finish and language before adding the card."
    },
    {
      "h2": "What the card photo scanner reads",
      "body": "- Card set identifier: the set attached to each suggested catalog match\n- Card number identifier: the collector or card number within that set\n- Card rarity: when that information is available in the catalog\n- Card variant and edition: details to verify against the selected record\n- Holo or foil finish: a field you confirm in Review before saving\n\nThis review step matters because near-identical printings can have different prices. The scan narrows the catalog; you confirm the specific copy you own."
    },
    {
      "h2": "Card search by photo, or by text",
      "body": "Camera scanning and text search reach the same catalog. Point the camera at a card for AI-assisted matching, or search by name, set or card number when the card is not in front of you.\n\nOpen the matching card record to review its available details and market prices before adding it to your collection."
    },
    {
      "h2": "Where image recognition struggles, and what to do",
      "body": "Card image recognition is at its weakest on near-identical printings: a reprint that reuses the artwork, a parallel that differs only by a foil pattern, or a card photographed at a bad angle under colored light.\n\nScan results are reviewed before they are added, which is where you confirm the printing. Good light, a flat card and a straight-on angle materially improve the first-pass result."
    }
  ],
  "faq": [
    {
      "q": "How does the AI card identifier tell near-identical printings apart?",
      "a": "It compares the photo with the card catalog and suggests likely matches with details such as set and card number. You review the candidates and confirm the matching card, finish and language before adding it."
    },
    {
      "q": "Can I identify a card without the card in hand?",
      "a": "Yes. Search the catalog by name, set or card number, then open the matching record to review its available printing details and prices."
    },
    {
      "q": "Does the card identifier app work across different games?",
      "a": "Yes. The same identifier covers Pokemon, Magic, Yu-Gi-Oh!, One Piece, Lorcana, Digimon, Dragon Ball Super, Star Wars Unlimited and Flesh and Blood, as well as basketball, football and soccer cards."
    },
    {
      "q": "Why does the variant matter so much?",
      "a": "Because price follows the printing, not the name. An alternate art or foil copy frequently trades at a multiple of the standard version at the same card number."
    }
  ],
  "related": [
    "card-price-checker",
    "bulk-card-scanner"
  ]
};
