export default {
  slug: 'card-ai-vs-ludex',
  group: 'feature',
  linkLabel: 'Card AI vs Ludex',
  ctaTarget: 'card scanner',
  title: 'Card AI vs Ludex: Scan, Price and List | Card AI',
  description: 'Compare the documented Card AI and Ludex workflows for reviewing card scans, researching prices, managing a collection, and listing on eBay.',
  eyebrow: 'Workflow comparison',
  h1: 'Card AI vs Ludex: scan to collection or scan to listing?',
  lede: 'Both products scan cards and support collections. The useful choice is what you need after the scan: confirm and track a holding, or prepare a card for sale.',
  proof: {
    kind: 'scan',
    title: 'Card AI makes each match a review decision.',
    body: 'Add up to 10 camera or gallery images to a queue. Confirm each candidate, finish and language before the card enters the [collection](/card-collection-tracker).',
  },
  cta: 'Try the Card AI review queue on a short stack of cards you already know.',
  sections: [
    {
      h2: 'The documented path after a scan',
      body: '| Step | Card AI | Ludex |\n| --- | --- | --- |\n| Review | Confirm a suggested catalog record, finish and language | Its [scan guide](https://www.ludex.com/scan-and-price/) says to verify card information and adjust the parallel |\n| Price context | Published prices and available history by raw condition or existing grade | The guide shows an estimated price, last sold price and sales-over-time report |\n| Next action | Add a confirmed holding to a collection | Add to collection or create an eBay listing |\n\nLudex also documents sports and TCG categories. Card AI supports basketball, football and soccer; category breadth alone is not a reason to claim one product is better.',
    },
    {
      h2: 'Choose based on selling plans',
      body: 'If you want to scan and publish an eBay listing, Ludex explicitly documents that handoff. Card AI currently offers an eBay search link for supported sports cards, not an in-app eBay listing tool. If you are sorting a stack into holdings and need raw copies and existing slabs valued separately, Card AI keeps those entries distinct in the portfolio.\n\nDo not treat a listing ask as a sold price. Review actual transaction evidence before deciding what to charge.',
    },
    {
      h2: 'How to compare the two fairly',
      body: 'Use the same known cards in both apps, including one base card, one parallel, and one graded slab. Record whether each result needs correction, how condition or grade is entered, and what happens after adding it to a collection. We have not run that controlled test, so this page does not claim a winner for recognition speed or accuracy.\n\n[Source: Ludex scan and price guide](https://www.ludex.com/scan-and-price/), reviewed October 19, 2026. Ludex plans and limits may change.',
    },
  ],
  faq: [
    { q: 'Is Card AI a Ludex alternative for organizing a stack?', a: 'Yes. Card AI queues up to 10 images for review and lets you add confirmed cards to a portfolio. Ludex also documents scanning and collection management; compare both on your own cards.' },
    { q: 'Can Card AI create an eBay listing like Ludex?', a: 'No. Ludex documents an eBay listing workflow. Card AI can provide an eBay search link for supported sports cards, but does not create an eBay listing.' },
    { q: 'Which scanner is more accurate?', a: 'We have not completed a controlled recognition test on the same cards in both apps, so we do not claim an accuracy winner.' },
  ],
  related: ['card-scanner-comparison-2026', 'bulk-card-scanner', 'card-collection-tracker'],
};
