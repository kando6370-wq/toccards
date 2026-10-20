export default {
  slug: 'card-ai-vs-collx',
  group: 'feature',
  linkLabel: 'Card AI vs CollX',
  ctaTarget: 'collection tracker',
  title: 'Card AI vs CollX: Prices and Collection | Card AI',
  description: 'Compare how Card AI and CollX identify variants, handle card condition and grades, explain prices, and organize a collection.',
  eyebrow: 'Pricing comparison',
  h1: 'Card AI vs CollX: what does the price represent?',
  lede: 'A scan can identify the right card and still leave a pricing question. Compare how each app records the copy you own and explains the value you see.',
  proof: {
    kind: 'prices',
    title: 'Card AI keeps the selected copy visible.',
    body: 'Confirm the printing, finish and language, then select a raw condition or the grade already on a slab. The [card price checker](/card-price-checker) shows the published price and available history for that record.',
  },
  cta: 'Check a raw card and an existing slab separately before adding either to your collection.',
  sections: [
    {
      h2: 'Variant, condition and price are separate decisions',
      body: '| Question | Card AI | CollX |\n| --- | --- | --- |\n| Which printing? | Suggests catalog candidates for you to confirm | Its [FAQ](https://www.collx.app/faq) says it shows multiple variants for selection and offers manual search |\n| What condition? | You choose a raw condition or enter the grade on an existing slab | Its FAQ says users manually enter condition or grade; it does not assess condition from a scan |\n| What does the value use? | Published market price for the confirmed record and available history; sports cards may link to eBay search | Its FAQ describes marketplace transactions, a median from recent sales, fallback last sale, and an estimate when direct sales are absent |\n| What happens next? | Keep distinct holdings in a portfolio | Add to collection; CollX also documents its marketplace |',
    },
    {
      h2: 'A useful test with two copies of one card',
      body: 'Take one raw copy and one PSA slab of the same printing. In each app, confirm the exact variant, enter the raw condition or slab grade, and note whether the displayed figure is a current estimate, a last sale or a historical trend. This makes an appraisal question concrete. Neither a scanner result nor a marketplace estimate authenticates the card.\n\nCollX is a fit if its built-in buy, sell and trade workflow matters to you. Card AI focuses on reviewed catalog records, condition-specific holdings and collection value. Both products support sports cards; neither should be described as uniquely supporting them.',
    },
    {
      h2: 'Read the source of the number',
      body: 'CollX explains its median, fallback and estimate rules in its [pricing FAQ](https://www.collx.app/faq). Card AI shows its published market price and available history; an eBay link for sports cards opens a separate search and is not a synced feed of sold transactions. Comparing those figures as if they are the same metric can mislead a seller.\n\nSources were reviewed October 19, 2026. We have not measured recognition or valuation accuracy on matched physical cards.',
    },
  ],
  faq: [
    { q: 'Does CollX identify raw card condition automatically?', a: 'CollX says in its FAQ that users enter condition or grade manually. Card AI also asks you to select raw condition or an existing slab grade.' },
    { q: 'Can I use both apps for sports cards?', a: 'Yes. CollX documents sports-card scanning, and Card AI supports basketball, football and soccer card workflows.' },
    { q: 'Are Card AI and CollX prices calculated the same way?', a: 'Do not assume so. CollX publishes a median and fallback methodology in its FAQ. Card AI shows a published market price and available history for the selected record; its eBay search link is separate.' },
  ],
  related: ['card-scanner-comparison-2026', 'card-price-checker', 'graded-card-tracker'],
};
