import { Hono } from "hono";
import type { Env } from "../env";

const PRODUCT_NAME = "Card AI";

const LEGAL_HEADERS = {
  "Cache-Control": "public, max-age=3600",
  "Content-Security-Policy":
    "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
} as const;

export function createLegalRoutes(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();

  routes.get("/legal/terms", (c) =>
    c.html(legalPage("Terms of Use", termsContent()), 200, LEGAL_HEADERS),
  );
  routes.get("/legal/privacy", (c) =>
    c.html(
      legalPage("Privacy Policy", privacyContent(), "July 17, 2026"),
      200,
      LEGAL_HEADERS,
    ),
  );
  routes.get("/legal/support", (c) =>
    c.html(legalPage("Support", supportContent()), 200, LEGAL_HEADERS),
  );

  return routes;
}

function legalPage(
  title: string,
  content: string,
  effectiveDate = "July 15, 2026",
): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title} | ${PRODUCT_NAME}</title>
  <style>
    :root { color-scheme: light; font-family: Inter, Arial, sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #f5f7f4; color: #20241e; line-height: 1.65; }
    header { background: #10120e; color: #f1f3e9; padding: 28px 20px; }
    header div, main { width: min(760px, 100%); margin: 0 auto; }
    .brand { color: #eefb70; font-size: 14px; font-weight: 700; letter-spacing: 0; }
    h1 { margin: 8px 0 0; font-size: clamp(28px, 6vw, 42px); line-height: 1.15; }
    main { padding: 28px 20px 56px; }
    h2 { margin: 30px 0 8px; font-size: 20px; line-height: 1.3; }
    p, li { font-size: 15px; }
    ul { padding-left: 22px; }
    a { color: #146b5c; }
    .effective { color: #596258; margin-top: 4px; }
    footer { border-top: 1px solid #d9ded7; margin-top: 36px; padding-top: 20px; color: #596258; }
  </style>
</head>
<body>
  <header><div><div class="brand">${PRODUCT_NAME.toUpperCase()}</div><h1>${title}</h1></div></header>
  <main>
    <p class="effective">Effective date: ${effectiveDate}</p>
    ${content}
    <footer>Questions may be sent to <a href="mailto:kando@tcgcard.fun">kando@tcgcard.fun</a>.</footer>
  </main>
</body>
</html>`;
}

function termsContent(): string {
  return `
    <p>These Terms of Use govern access to the ${PRODUCT_NAME} application and related services. By using ${PRODUCT_NAME}, you agree to these terms.</p>
    <h2>1. Eligibility and accounts</h2>
    <p>You must be legally able to enter into these terms. If you are under the age of majority where you live, a parent or guardian must approve your use. You are responsible for activity under your account and for keeping access credentials secure.</p>
    <h2>2. The service</h2>
    <p>${PRODUCT_NAME} helps collectors identify trading cards, organize Portfolio folders, maintain a Wishlist, and view market information. Scanned cards are not added to a Portfolio until you review and confirm them.</p>
    <h2>3. Card and price information</h2>
    <p>Card recognition, catalog details, market prices, sales history, and currency conversions may be supplied by third parties and can be incomplete, delayed, or inaccurate. They are estimates for collection management only and are not financial, investment, appraisal, tax, or legal advice.</p>
    <h2>4. Your content</h2>
    <p>You retain ownership of card images, notes, and other content you submit. You grant ${PRODUCT_NAME} a limited license to process that content only as needed to provide, secure, support, and improve the service.</p>
    <h2>5. Acceptable use</h2>
    <ul>
      <li>Do not use ${PRODUCT_NAME} for unlawful, fraudulent, abusive, or infringing activity.</li>
      <li>Do not interfere with the service, bypass access controls, or attempt unauthorized access.</li>
      <li>Do not upload malicious code or content that violates another person's rights.</li>
    </ul>
    <h2>6. Third-party services</h2>
    <p>${PRODUCT_NAME} relies on service providers for hosting, sign-in, email, card recognition, and card data. Their services may have separate terms and may change or become unavailable.</p>
    <h2>7. Availability and changes</h2>
    <p>We may update, suspend, or discontinue features to maintain security, comply with law, or improve ${PRODUCT_NAME}. We do not guarantee uninterrupted or error-free availability.</p>
    <h2>8. Disclaimers and liability</h2>
    <p>${PRODUCT_NAME} is provided on an "as is" and "as available" basis to the extent permitted by law. To the maximum extent permitted by law, ${PRODUCT_NAME} is not liable for indirect, incidental, special, consequential, or lost-profit damages, or for decisions made from card or price information. Rights that cannot legally be excluded remain unaffected.</p>
    <h2>9. Suspension and termination</h2>
    <p>You may stop using ${PRODUCT_NAME} or request account deletion in the app. We may restrict access when reasonably necessary for security, abuse prevention, legal compliance, or a material violation of these terms.</p>
    <h2>10. Changes to these terms</h2>
    <p>We may revise these terms. Material changes will be communicated through the app or another reasonable channel, and the effective date above will be updated.</p>`;
}

function privacyContent(): string {
  return `
    <p>This Privacy Policy explains how ${PRODUCT_NAME} handles information when you use the application and related services.</p>
    <h2>1. Information we process</h2>
    <ul>
      <li><strong>Account information:</strong> email address, account identifiers, sign-in provider identifiers, and session records.</li>
      <li><strong>Collection information:</strong> Portfolio folders, card references, quantities, grading details, purchase values, notes, Wishlist entries, and preferences.</li>
      <li><strong>Scan information:</strong> perspective-corrected card-area images, perceptual hashes derived from those images, recognition candidates, confirmation results, filename, app version, platform, and available device or operating-system metadata.</li>
      <li><strong>Support information:</strong> feedback category, message, optional contact details, and related service records.</li>
      <li><strong>Technical information:</strong> network requests, security events, and diagnostics needed to operate and protect the service.</li>
    </ul>
    <h2>2. How we use information</h2>
    <p>We use information to authenticate users, recognize cards, maintain collections and preferences, show relevant card and price data, answer support requests, prevent abuse, troubleshoot failures, and comply with legal obligations.</p>
    <h2>3. Service providers</h2>
    <p>Information may be processed by providers that support ${PRODUCT_NAME}, including Cloudflare for hosting and storage, Apple and Google for sign-in, Zoho for service email, card-recognition infrastructure, and card-data providers. Providers process information under their own security and privacy obligations.</p>
    <h2>4. Card images</h2>
    <p>Selected images are processed on your device to detect and perspective-correct the card area and derive RGB perceptual hashes. The corrected card-area crop, not the surrounding camera frame, is uploaded to a private Cloudflare R2 bucket for scan records, customer support, and recognition-quality auditing. The external card-recognition service receives only the RGB perceptual hashes and an optional game identifier; it does not receive the card image.</p>
    <h2>5. Sharing and sale</h2>
    <p>We do not sell personal information. We disclose information only to service providers, when you direct us to, to protect users and the service, during a business reorganization, or when required by law.</p>
    <h2>6. Retention and deletion</h2>
    <p>Uploaded card-area images and their scan records are retained without a fixed expiration period for scan auditing, customer support, and recognition-quality review. Deleting an account does not delete these retained scan images or scan records. Other information is retained only for configured periods needed to provide ${PRODUCT_NAME}, meet security and legal requirements, resolve disputes, and maintain backups.</p>
    <h2>7. Security</h2>
    <p>We use technical and organizational safeguards designed to protect information. No storage or transmission method is completely secure.</p>
    <h2>8. International processing</h2>
    <p>${PRODUCT_NAME} and its providers may process information in countries other than your own. Where required, appropriate safeguards are used for international transfers.</p>
    <h2>9. Your choices and rights</h2>
    <p>Depending on where you live, you may have rights to access, correct, delete, restrict, or obtain a copy of personal information, or object to certain processing. Contact us to exercise a right. You may also manage collection data and preferences in the app.</p>
    <h2>10. Children</h2>
    <p>${PRODUCT_NAME} is not directed to children under 13, and we do not knowingly collect personal information from children under 13. Contact us if you believe a child has provided information.</p>
    <h2>11. Changes to this policy</h2>
    <p>We may update this policy as ${PRODUCT_NAME} changes. Material updates will be communicated through the app or another reasonable channel, and the effective date above will be revised.</p>`;
}

function supportContent(): string {
  return `
    <p>Get help with ${PRODUCT_NAME} scanning, account access, collection data, and app settings.</p>
    <h2>Contact support</h2>
    <p>Open Profile in the app and select Customer Support to send a request with the relevant category and details. You may also email <a href="mailto:kando@tcgcard.fun">kando@tcgcard.fun</a>.</p>
    <p>Do not send passwords, verification codes, or payment information in a support request.</p>
    <h2>Account deletion</h2>
    <p>You can delete your account from Profile &gt; Account &gt; Delete account. If you cannot access the app, contact support from the email address associated with your account.</p>
    <h2>Policies</h2>
    <p>Review the <a href="/api/v1/legal/terms">Terms of Use</a> and <a href="/api/v1/legal/privacy">Privacy Policy</a> for service and data-handling details.</p>`;
}
