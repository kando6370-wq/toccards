import { Hono } from "hono";
import type { Env } from "../env";

const PRODUCT_NAME = "CardScanFox";

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
    c.html(
      legalPage(
        "Terms of Use",
        termsContent(),
        "November 17, 2026",
        true,
        "support@tcgcard.fun",
      ),
      200,
      LEGAL_HEADERS,
    ),
  );
  routes.get("/legal/privacy", (c) =>
    c.html(
      legalPage(
        "Privacy Policy",
        privacyContent(),
        "November 17, 2026",
        true,
        "support@tcgcard.fun",
      ),
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
  isVersionDate = false,
  contactEmail = "kando@tcgcard.fun",
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
    main { padding: 28px 20px 56px; overflow-wrap: anywhere; }
    h2 { margin: 30px 0 8px; font-size: 20px; line-height: 1.3; }
    p, li { font-size: 15px; }
    ul { padding-left: 22px; }
    li > p { margin: 0; }
    a { color: #146b5c; }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    th, td { border: 1px solid #cbd2c9; padding: 10px; text-align: left; vertical-align: top; overflow-wrap: anywhere; }
    pre { max-width: 100%; overflow-x: auto; padding: 16px; background: #e9ede7; white-space: pre-wrap; overflow-wrap: anywhere; }
    code { font-family: ui-monospace, SFMono-Regular, Consolas, monospace; }
    .effective { color: #596258; margin-top: 4px; }
    footer { border-top: 1px solid #d9ded7; margin-top: 36px; padding-top: 20px; color: #596258; }
  </style>
</head>
<body>
  <header><div><div class="brand">${PRODUCT_NAME.toUpperCase()}</div><h1>${title}</h1></div></header>
  <main>
    <p class="effective">${isVersionDate ? "Version date" : "Effective date"}: ${effectiveDate}</p>
    ${content}
    <footer>Questions may be sent to <a href="mailto:${contactEmail}">${contactEmail}</a>.</footer>
  </main>
</body>
</html>`;
}

function termsContent(): string {
  return `
<p>These Terms of Use (“Terms”) apply to your access to and use of <strong>CardScanFox: TCG Card Scanner</strong> and any related mobile application, website, features, content, subscriptions, and services provided by <strong>CardScanFox: TCG Card Scanner</strong> (“CardScanFox,” “we,” “us,” or “our”).</p>
<p>By downloading, installing, accessing, or using CardScanFox, you agree to these Terms. If you do not agree to these Terms, please do not use the app.</p>
<h2>1. Our Service</h2>
<p>CardScanFox is a mobile app designed to help users scan, search, identify, organize, and track trading cards and sports cards.</p>
<p>The app may provide features including:</p>
<ul>
<li><p>Card scanning and identification</p>
</li>
<li><p>Card information lookup</p>
</li>
<li><p>Price and value reference</p>
</li>
<li><p>Collection tracking</p>
</li>
<li><p>Portfolio management</p>
</li>
<li><p>Wishlist or saved card features</p>
</li>
<li><p>Raw and graded card information when available</p>
</li>
<li><p>Support for selected TCG and sports card categories</p>
</li>
</ul>
<p>CardScanFox currently supports or may support categories including Pokémon, Magic: The Gathering, One Piece, Yu-Gi-Oh!, Disney Lorcana, Digimon, Star Wars: Unlimited, Flesh and Blood, basketball cards, baseball cards, and football cards.</p>
<p>Feature availability depends on platform and app version. We may update or change the Service subject to applicable notice requirements, paid entitlements, and mandatory consumer rights.</p>
<h2>2. Eligibility</h2>
<p>You must be at least 13 years old to use CardScanFox. If you are under the age of majority in your country or region, you may use CardScanFox only with permission from a parent or legal guardian.</p>
<p>By using CardScanFox, you confirm that you are legally able to agree to these Terms and that your use of the Service complies with applicable laws.</p>
<h2>3. Accounts and Platform Separation</h2>
<p>Android offers guest access, email-and-password registration, and Google sign-in. iOS offers the supported sign-in methods shown in the iOS app. You are responsible for supplying accurate account information and protecting your credentials and device. Contact support if you suspect unauthorized access.</p>
<p>Android and iOS use separate platform accounts and personal data spaces, even where databases or authentication infrastructure are shared. Using the same email address or sign-in provider on both platforms does not merge or synchronize collections, Wishlist, folders, scan records, preferences, or collection-value records. Public card catalog and reference prices may be shared.</p>
<p>Apple purchase rights apply to iOS. Free Android access does not require an Apple subscription and does not grant an iOS subscription. Guest access may involve locally stored or server-side records and technical identifiers as described in the Privacy Policy.</p>
<h2>4. Account and Data Deletion</h2>
<p>You can initiate deletion through <strong>Delete Account</strong> in the app&#39;s account settings, visit <a href="https://tcgcard.fun/Account/AccountSetup">our account deletion page</a>, or email <a href="mailto:support@tcgcard.fun">support@tcgcard.fun</a>. Specify the platform, Android or iOS, and the relevant account. If the page opens an email draft, you must send it. You do not need to reinstall the app to request deletion. We may verify your identity; never send your password or verification codes.</p>
<p>Once a verified deletion is executed, we immediately delete the selected platform account and its associated information on our own servers, including collections, Wishlist, folders, saved card details, uploaded scan images and records, and preferences. We do not retain those deleted records on our servers for account recovery. Support requests may require review and verification before execution.</p>
<p>Deletion ends access through that platform account&#39;s sessions and is permanent. <strong>You must register again to use an account on that platform. Reusing the same email address or Google sign-in does not restore deleted data.</strong> The other platform&#39;s separate account and records remain unaffected. A shared authentication record needed by the other active platform does not reactivate the deleted account.</p>
<p>The immediate deletion of our server records does not imply simultaneous deletion of third-party analytics, attribution, diagnostic, or Apple transaction records. Their treatment and available privacy requests are explained in the <a href="https://tcgcard.fun/privacy">Privacy Policy</a>.</p>
<p>Deleting the app or your CardScanFox account does not cancel an Apple subscription or delete your Apple or Google account. Manage Apple subscriptions in your Apple account settings. Subscription cancellation is not required before submitting an account-deletion request. Uninstalling alone does not delete a server account. Contact support for help deleting guest data or both platform accounts.</p>
<h2>5. Card Scanning</h2>
<p>Scanning uses your camera or images you select from your photo library. The images are uploaded to our server for recognition. Uploaded images and associated scan records are retained until deletion of the relevant platform account, unless removed earlier through an available deletion feature. <strong>We do not use your uploaded images or scan records for model training.</strong></p>
<p>Recognition can be affected by lighting, image quality, card condition, language, finish, edition, or catalog coverage. Review the suggested match before saving a card or relying on its information. Card recognition is not a guarantee of authenticity or a professional grading service.</p>
<p>The current Android release supports a maximum of 10 cards in a scan batch. When the pending batch reaches that limit, you must save cards to your collection or delete pending results before continuing. The iOS free-scan allowance does not impose a lifetime 10-scan allowance on Android.</p>
<p>Only upload content that you are entitled to use. Do not upload unlawful content or images that infringe another person&#39;s privacy or intellectual-property rights.</p>
<h2>6. Card Data, Prices, and Value Information</h2>
<p>CardScanFox may display card information, market prices, estimated values, historical data, grading-related information, collection totals, or other reference data.</p>
<p>You understand and agree that:</p>
<ul>
<li><p>Card data and price information may be incomplete, delayed, unavailable, inaccurate, or based on third-party sources.</p>
</li>
<li><p>Price and value information is provided for general informational purposes only.</p>
</li>
<li><p>CardScanFox does not provide financial, investment, appraisal, grading, tax, legal, or professional advice.</p>
</li>
<li><p>Displayed values do not guarantee that a card can be bought or sold at that price.</p>
</li>
<li><p>Actual market prices may vary based on condition, grading, authenticity, demand, platform fees, shipping, taxes, buyer behavior, seller behavior, and other factors.</p>
</li>
<li><p>You are responsible for independently verifying any information before buying, selling, grading, trading, insuring, or valuing any card.</p>
</li>
</ul>
<p>We are not responsible for losses, decisions, transactions, missed opportunities, or disputes arising from your reliance on card data, scan results, price estimates, or value information shown in the app.</p>
<h2>7. Collection Records</h2>
<p>CardScanFox may allow you to save cards, edit collection details, add purchase prices, set quantities, choose finishes, record grading information, organize cards, and track collection value.</p>
<p>You are responsible for the accuracy of information you manually enter or edit. We do not guarantee that your collection value, portfolio value, profit/loss calculation, or related analytics will always be complete or accurate.</p>
<p>You should keep your own backup of important records where necessary.</p>
<h2>8. Platform Access, Subscriptions, and In-App Purchases</h2>
<h3>Android</h3>
<p>The current Android release provides its available features without subscriptions or in-app purchases and does not include AI Grade. Free Android access is separate from iOS purchase entitlements. If paid Android features are introduced later, their prices and conditions will be disclosed before purchase; use of the current free release does not authorize a future charge.</p>
<h3>iOS</h3>
<p>On iOS, CardScanFox may offer paid subscriptions, free trials, premium features, or other in-app purchases through Apple’s in-app purchase system.</p>
<p>If you purchase a subscription:</p>
<ul>
<li><p>Payment will be charged to your Apple ID account at confirmation of purchase.</p>
</li>
<li><p>Subscriptions automatically renew unless canceled at least 24 hours before the end of the current subscription period.</p>
</li>
<li><p>Your account may be charged for renewal within 24 hours before the end of the current period.</p>
</li>
<li><p>You can manage or cancel your subscription in your Apple ID account settings.</p>
</li>
<li><p>Deleting the app or deleting your CardScanFox account does not automatically cancel your subscription.</p>
</li>
<li><p>Any unused portion of a free trial may be forfeited when you purchase a subscription, where applicable.</p>
</li>
<li><p>Prices, subscription periods, available features, and free trial offers may vary by country, region, user, promotional campaign, or App Store settings.</p>
</li>
</ul>
<p>All billing, refunds, cancellations, and payment issues for App Store purchases are handled by Apple under Apple’s policies. We cannot directly cancel, refund, or modify App Store transactions unless Apple provides us with the ability to do so.</p>
<p>Premium features may change over time. We may add, remove, modify, or limit premium features, provided that we do not materially reduce the core functionality of an active paid subscription without appropriate notice where required by law.</p>
<p>A non-renewing one-time purchase, when offered, is charged once and does not automatically renew. Its scope is the entitlement described at purchase. A lifetime purchase does not mean ownership of the Service or a guarantee that the Service will operate indefinitely. Mandatory consumer rights remain unaffected.</p>
<p>Restore Purchases on iOS uses eligible purchase information supplied by Apple. Restoring a purchase does not restore deleted collections or other deleted account records, and it does not transfer Apple entitlements to Android.</p>
<h2>9. Acceptable Use</h2>
<p>You agree not to:</p>
<ul>
<li><p>Use the Service for unlawful, fraudulent, harmful, abusive, or unauthorized purposes.</p>
</li>
<li><p>Reverse engineer, decompile, modify, copy, distribute, sell, lease, or create derivative works based on the app or any part of the Service, except where permitted by applicable law or the relevant open-source license.</p>
</li>
<li><p>Attempt to access, scrape, extract, collect, or use data from the Service through automated means without our permission.</p>
</li>
<li><p>Interfere with or disrupt the Service, servers, security systems, or networks.</p>
</li>
<li><p>Upload or submit content that infringes third-party rights, including intellectual property or privacy rights.</p>
</li>
<li><p>Use the Service to impersonate another person or misrepresent your identity.</p>
</li>
<li><p>Use the Service in a way that may damage, disable, overload, or impair the app.</p>
</li>
<li><p>Circumvent subscription limits, usage limits, technical restrictions, or access controls.</p>
</li>
<li><p>Use card images, data, or other content in a way that violates applicable laws or third-party rights.</p>
</li>
</ul>
<p>We may suspend, restrict, or terminate access to the Service if we believe you have violated these Terms, applicable laws, or the rights of others.</p>
<h2>10. Third-Party Services</h2>
<p>We use Firebase, including analytics and Crashlytics, Mixpanel, and Singular for relevant analytics, diagnostics, and marketing-attribution functions. Supported Google and Apple services provide sign-in or iOS payment functions. Infrastructure providers support hosting, storage, and server-side recognition.</p>
<p>The <a href="https://tcgcard.fun/privacy">Privacy Policy</a> explains the information involved and the applicable platform differences. Independent services you choose to access have their own terms. These Terms do not remove our obligations for service providers processing information on our behalf.</p>
<h2>11. Third-Party Links and Marketplaces</h2>
<p>CardScanFox may include links, references, or integrations that direct you to third-party websites, marketplaces, platforms, sellers, grading companies, or other external services.</p>
<p>We do not control third-party websites or services and are not responsible for their content, prices, availability, accuracy, policies, transactions, fees, shipping, taxes, disputes, or security.</p>
<p>If you choose to access or use third-party services, you do so at your own risk and subject to their own terms and policies.</p>
<h2>12. Intellectual Property</h2>
<p>CardScanFox, including its software, design, interface, features, graphics, logos, text, code, databases, and other content, is owned by us or our licensors and is protected by intellectual property and other laws.</p>
<p>These Terms grant you a limited, personal, non-exclusive, non-transferable, revocable license to use CardScanFox for your own personal, non-commercial use, subject to these Terms.</p>
<p>You do not acquire any ownership rights in CardScanFox or any part of the Service.</p>
<h2>13. User Content</h2>
<p>You may submit, upload, save, or enter content into the Service, including card images, collection records, notes, purchase prices, grading details, or other information (“User Content”).</p>
<p>You retain any rights you may have in your User Content. By using the Service, you grant us a limited license to host, store, process, display, reproduce, and use your User Content only as necessary to host your records and operate, provide, secure, and support the Service. This license does not permit using your uploaded images or scan records for model training. Its exercise remains subject to the retention and deletion provisions of the Privacy Policy.</p>
<p>You represent that you have the necessary rights to submit your User Content and that your User Content does not violate any law or third-party rights.</p>
<h2>14. Trademarks and Brand Disclaimer</h2>
<p>CardScanFox is an independent app and is not affiliated with, endorsed by, sponsored by, or officially connected with any trading card game publisher, sports league, team, player, grading company, marketplace, manufacturer, or rights holder.</p>
<p>All trademarks, logos, card names, set names, character names, brand names, images, and other intellectual property belong to their respective owners.</p>
<p>This includes, without limitation, The Pokémon Company, Nintendo, GAME FREAK, Creatures Inc., Wizards of the Coast, Hasbro, Konami, Bandai, Disney, Lucasfilm, Legend Story Studios, PSA, BGS, CGC, eBay, TCGplayer, and any applicable sports leagues, teams, players, manufacturers, or marketplaces.</p>
<p>Any reference to third-party brands, cards, games, teams, players, or marketplaces is for identification, compatibility, reference, or informational purposes only.</p>
<h2>15. Privacy</h2>
<p>Your privacy is important to us. Our collection, use, storage, sharing, and protection of personal data is described in our Privacy Policy.</p>
<p>The Privacy Policy explains our data practices. Acceptance of these Terms does not substitute for a separate consent or device permission where one is required.</p>
<p>Privacy Policy: <a href="https://tcgcard.fun/privacy">https://tcgcard.fun/privacy</a></p>
<h2>16. App Updates and Availability</h2>
<p>We may release updates, bug fixes, improvements, or new features from time to time. Some features may require you to install the latest version of the app.</p>
<p>We do not guarantee that CardScanFox will always be available, uninterrupted, secure, error-free, or compatible with every device, operating system, region, network, or App Store account.</p>
<p>We may suspend or discontinue all or part of the Service subject to applicable notice, refund, and other mandatory consumer-protection requirements.</p>
<h2>17. Disclaimers</h2>
<p>CardScanFox is provided on an “as is” and “as available” basis.</p>
<p>To the maximum extent permitted by applicable law, we disclaim all warranties, whether express, implied, statutory, or otherwise, including warranties of merchantability, fitness for a particular purpose, title, non-infringement, accuracy, availability, and reliability.</p>
<p>We do not guarantee that:</p>
<ul>
<li><p>Scan results will be correct.</p>
</li>
<li><p>Card data will be complete or current.</p>
</li>
<li><p>Price or value estimates will be accurate.</p>
</li>
<li><p>Collection totals or analytics will be error-free.</p>
</li>
<li><p>The Service will meet your expectations.</p>
</li>
<li><p>The Service will operate without interruption or defects.</p>
</li>
</ul>
<p>You use CardScanFox at your own risk.</p>
<h2>18. Limitation of Liability</h2>
<p>To the maximum extent permitted by applicable law, we and our affiliates, officers, directors, employees, contractors, licensors, and service providers will not be liable for any indirect, incidental, special, consequential, exemplary, or punitive damages, including loss of profits, data, goodwill, business opportunities, collection value, or any losses arising from or related to reliance on card identification results, price or market-value information, condition or grading estimates, third-party marketplace links, or purchase, sale, grading, or other transaction decisions.</p>
<p>To the maximum extent permitted by applicable law, our aggregate liability for all claims arising out of or relating to the Service or these Terms will not exceed the greater of: (a) the amount you actually paid to us for the Service during the 12 months immediately preceding the event giving rise to the claim; or (b) US$100.</p>
<p>Nothing in these Terms excludes or limits any liability that cannot lawfully be excluded or limited. Some jurisdictions do not allow certain exclusions or limitations of liability, so some of the above provisions may not apply to you.</p>
<h2>19. Indemnification</h2>
<p>To the maximum extent permitted by applicable law, you agree to defend, indemnify, and hold harmless CardScanFox, and our affiliates, officers, directors, employees, contractors, licensors, service providers, and partners from and against any claims, damages, losses, liabilities, costs, and expenses, including reasonable attorneys’ fees, arising out of or related to:</p>
<ul>
<li><p>your use or misuse of the Service;</p>
</li>
<li><p>your violation of these Terms;</p>
</li>
<li><p>your violation of applicable laws;</p>
</li>
<li><p>your User Content;</p>
</li>
<li><p>your violation of third-party rights;</p>
</li>
<li><p>your transactions, purchases, sales, grading submissions, or other decisions made based on information from the Service.</p>
</li>
</ul>
<h2>20. Termination</h2>
<p>You may stop using CardScanFox at any time.</p>
<p>We may suspend, restrict, or terminate your access to the Service at any time if we believe you have violated these Terms, created risk or legal exposure for us, or used the Service in a harmful, fraudulent, abusive, or unlawful way.</p>
<p>After termination, sections that by their nature should survive will remain in effect, including intellectual property, disclaimers, limitation of liability, indemnification, privacy-related provisions, and dispute provisions.</p>
<h2>21. Changes to These Terms</h2>
<p>We may update these Terms from time to time. When we update the Terms, we will revise the version date above and state when the revised Terms take effect. This version takes effect upon publication on our website.</p>
<p>If we make material changes, we may notify you through the app, by email, on our website, or by other reasonable means where required by law.</p>
<p>Your continued use of CardScanFox after the updated Terms become effective means you accept the updated Terms.</p>
<h2>22. Governing Law</h2>
<p>These Terms shall be governed by and construed in accordance with applicable laws, without regard to conflict of law principles.</p>
<p>If you are a consumer located in a jurisdiction with mandatory consumer protection rights, these Terms do not limit any rights you may have under applicable laws.</p>
<h2>23.OPEN SOURCE AND MODEL LICENSES</h2>
<p>The App includes the RTMDet-Ins Card Detector and converted forms of the PE-Core-T16-384 image encoder. Copyright in the project-authored RTMDet-Ins model weights and conversions is held by <strong>Chongqing Guanyun Technology Co.,ltd.</strong>. PE-Core-T16-384 was developed by Meta. These models and their converted or modified forms are used under the Apache License, Version 2.0. The conversions and modifications made for this App were not created, reviewed, or endorsed by Meta.</p>
<p>The RTMDet-Ins Card Detector was trained using modified materials derived from “cards-keypoints v1” by Norbert Gierczak and “Card-SEG v10 PhoneCardSegV1” by nandersen, each licensed under CC BY 4.0. The source images and annotations were converted, normalized, rotated, and adapted for model training. The original creators do not endorse these modifications or this App. CC BY 4.0 license: <a href="https://creativecommons.org/licenses/by/4.0/">https://creativecommons.org/licenses/by/4.0/</a></p>
<p>The Android version of the App includes Microsoft ONNX Runtime 1.23.0 under the MIT License. All referenced software, models, datasets, and converted materials are provided on an “AS IS” basis without warranties. Their licenses do not grant rights to any card artwork, photographs, game or team logos, player likenesses, product names, or trademarks. The applicable Apache 2.0, MIT, and ONNX Runtime third-party notices are reproduced below.</p>
<h4>▸ Apache License 2.0</h4>
<p>The following license applies to the RTMDet-Ins trained weights and converted forms and to PE-Core-T16-384 and its converted forms as described above.</p>
<pre><code class="language-text">                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      &quot;License&quot; shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      &quot;Licensor&quot; shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      &quot;Legal Entity&quot; shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      &quot;control&quot; means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      &quot;You&quot; (or &quot;Your&quot;) shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      &quot;Source&quot; form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      &quot;Object&quot; form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      &quot;Work&quot; shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      &quot;Derivative Works&quot; shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      &quot;Contribution&quot; shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, &quot;submitted&quot;
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as &quot;Not a Contribution.&quot;

      &quot;Contributor&quot; shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a &quot;NOTICE&quot; text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an &quot;AS IS&quot; BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

</code></pre>
<h4>▸ MIT License</h4>
<p>Copyright (c) Microsoft Corporation</p>
<p>Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the &quot;Software&quot;), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:</p>
<p>The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.</p>
<p>THE SOFTWARE IS PROVIDED &quot;AS IS&quot;, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.</p>
<h4>▸Development Tools Not Included in the Application</h4>
<p>MMDetection, MMCV, MMEngine, MMDeploy, ONNX, and OpenCV were used in model training, conversion, validation, or as preprocessing references. Their libraries are not included in the current mobile application. In particular, the mobile image-resize implementation matches OpenCV&#39;s half-pixel bilinear sampling behavior but does not include OpenCV.</p>
<h2>24. Contact Us</h2>
<p>Support: <a href="mailto:support@tcgcard.fun">support@tcgcard.fun</a>   Website: <a href="https://tcgcard.fun">https://tcgcard.fun</a>   Privacy Policy: <a href="https://tcgcard.fun/privacy">https://tcgcard.fun/privacy</a>   Terms of Use: <a href="https://tcgcard.fun/terms">https://tcgcard.fun/terms</a>   Account deletion: <a href="https://tcgcard.fun/Account/AccountSetup">https://tcgcard.fun/Account/AccountSetup</a></p>
`;
}

function privacyContent(): string {
  return `
<p>This Privacy Policy explains how <strong>CardScanFox: TCG Card Scanner</strong> (“CardScanFox,” “we,” “us,” or “our”) collects, uses, stores, discloses, and deletes information when you use our iOS and Android applications and related account and support services (the “Service”). Platform-specific practices are identified below.</p>
<p>For privacy questions or requests, contact <a href="mailto:support@tcgcard.fun">support@tcgcard.fun</a>. Our website is <a href="https://tcgcard.fun">https://tcgcard.fun</a>.</p>
<h2>1. Information We Collect and Why</h2>
<h3>Account and sign-in information</h3>
<p>When you register or sign in, we process your email address, account or provider user ID, authentication information, account settings, and session information to create and secure your account. Email-and-password registration involves processing the credentials you submit. Supported third-party sign-in methods provide authentication results and the account information authorized by that method. We do not receive your Google or Apple account password when you use their sign-in services.</p>
<p>Android supports guest access, email-and-password accounts, and Google sign-in. iOS offers the sign-in methods displayed in the iOS app. An email address ending in gmail.com is treated as an email address; using it with a CardScanFox password is different from using Google sign-in.</p>
<p>Guest access does not require you to supply an account email, but use of the Service may still generate scan records, technical identifiers, and usage information.</p>
<h3>Card images and scan records</h3>
<p>When you scan a card or import a photo for recognition, <strong>the image is uploaded to our server for identification</strong>. We process the image and associated recognition results to provide scanning and scan-record features. Uploaded scan images and associated scan records are stored until you delete the relevant platform account, unless you delete them earlier using an available deletion feature.</p>
<p><strong>We do not use your uploaded images or scan records to train machine-learning or AI models.</strong> Processing an image with an existing recognition model is used to provide the requested recognition result.</p>
<p>We use the camera when you initiate scanning and grant the necessary permission. Photo import accesses images you select or authorize through your device&#39;s photo-access controls. You can manage these permissions in device settings. Refusing permission may prevent the corresponding scanning or import feature from working.</p>
<h3>Collections and information you enter</h3>
<p>We store collection and Wishlist records, folder names, card selections, quantities, finishes, languages, purchase prices, grading details, preferences, and other information you enter into supported features. We use these records to organize your collection and provide price references, collection values, and related charts. A manually entered card purchase price is collection data; it is not your payment-card or bank-account information.</p>
<h3>Search and app activity</h3>
<p>Search terms, such as card names or numbers, are sent to our systems when needed to return search results. We do not maintain a saved user search-history feature. Processing a search request is separate from displaying or storing a searchable history in the app.</p>
<p>Our analytics services process configured events such as screen views, button taps, sessions, and scan success or failure. We use these events to understand feature usage and improve the app. Search-related events may record use of the search feature; this does not itself mean that the text of every search is included in analytics.</p>
<h3>Device information, diagnostics, and approximate location</h3>
<p>The app and its SDKs process device and app information, such as device model, operating-system and app versions, language, IP address, app-instance and installation identifiers, and configured usage events. Firebase Crashlytics processes crash reports, stack traces, relevant application and device state, and installation identifiers to diagnose errors.</p>
<p>Analytics services may derive approximate location, such as country, region, or city, from your IP address. This does not require your device&#39;s location permission. <strong>We do not request or collect precise GPS location.</strong></p>
<h3>Advertising attribution</h3>
<p>We use Singular and relevant analytics integrations to measure installation sources and advertising campaign results. This may involve advertising identifiers when available and permitted, install-referrer information, IP address, device/app details, and configured conversion events.</p>
<p>The Android app does not display in-app advertisements. Attribution is used to measure advertisements for CardScanFox shown outside the app. Having no in-app advertisements does not mean that attribution data is not processed.</p>
<p>On iOS, access to the advertising identifier and tracking subject to Apple&#39;s permission requirements depend on the applicable device permission. On Android, the availability of the advertising identifier depends on device settings and applicable platform controls.</p>
<h3>iOS purchases</h3>
<p>Apple handles payment for purchases made through the App Store. To determine iOS access to purchased features, the iOS app uses purchase and subscription information supplied by Apple, such as product identifiers, transaction information, and current entitlement status. We do not receive your complete payment-card details from Apple.</p>
<p>The current Android release has no subscriptions or in-app purchases. Apple purchase rights are not used to restrict access to the free Android release.</p>
<h3>Support communications</h3>
<p>If you email us or submit a support or deletion request, we process your contact information, message, and any attachments you voluntarily provide to respond and handle the request. We do not access your email inbox or collect unrelated emails from your device.</p>
<h2>2. How We Use Information</h2>
<p>We process information to:</p>
<ul>
<li><p>Provide scanning, search, collection management, and price-reference features.</p>
</li>
<li><p>Register, authenticate, and manage accounts and sessions.</p>
</li>
<li><p>Store and retrieve records within the relevant platform account.</p>
</li>
<li><p>Determine iOS purchase access and provide free Android access.</p>
</li>
<li><p>Analyze feature usage, diagnose crashes, and improve reliability.</p>
</li>
<li><p>Measure advertising and installation attribution.</p>
</li>
<li><p>Respond to support requests and send necessary account or service notices.</p>
</li>
<li><p>Protect the Service against unauthorized access and abuse, and meet applicable legal obligations.</p>
</li>
</ul>
<p>We do not use card images or scan records for model training. A reference to product improvement in this policy does not authorize such training.</p>
<p>Where applicable law requires a legal basis, processing is based on providing the service you request, our legitimate interests in operating and protecting the Service where permitted, compliance with legal obligations, or consent where required. You may withdraw consent for consent-based processing without affecting processing that was lawful before withdrawal.</p>
<h2>3. Android and iOS Data Separation</h2>
<p>Android and iOS have <strong>separate platform accounts and personal data spaces</strong>, even where they use shared databases or authentication infrastructure.</p>
<p>Signing in with the same email address or identity provider on both platforms does not automatically merge or synchronize collections, Wishlist, folders, scan images or records, preferences, or collection-value records. Public card catalog and price-reference data may be shared between platforms.</p>
<p>Apple purchase entitlements apply to iOS. Android free access is separate. Deleting one platform account does not delete the separate account or records on the other platform. A shared authentication record needed for the other active platform may remain for that purpose; it does not restore the deleted platform account.</p>
<h2>4. Service Providers and Other Recipients</h2>
<p>Our analytics, attribution, and crash-reporting SDK providers are <strong>Firebase, Mixpanel, and Singular</strong>.</p>
<table>
<thead>
<tr>
<th>Provider or recipient</th>
<th>Relevant information and purposes</th>
</tr>
</thead>
<tbody><tr>
<td>Firebase / Google Analytics for Firebase</td>
<td>App-instance identifiers, device/app information, configured usage events, and IP-derived approximate location for usage analysis.</td>
</tr>
<tr>
<td>Firebase Crashlytics</td>
<td>Crash reports, diagnostics, application/device state, installation identifiers, and any diagnostic context attached to reports, to investigate and fix errors.</td>
</tr>
<tr>
<td>Mixpanel</td>
<td>Configured events, user or pseudonymous identifiers, device/app information, and IP-derived approximate location for product analytics.</td>
</tr>
<tr>
<td>Singular</td>
<td>Available advertising identifiers, install/referrer and attribution information, IP address, device/app details, and configured conversion events for campaign measurement.</td>
</tr>
<tr>
<td>Google and Apple sign-in services</td>
<td>Authentication information and authorized account information when you choose a supported sign-in method. Apple sign-in is an iOS feature.</td>
</tr>
<tr>
<td>Apple App Store</td>
<td>Purchase, subscription, and entitlement information for iOS purchases; Apple independently handles billing and its own transaction records.</td>
</tr>
<tr>
<td>Infrastructure service providers</td>
<td>The account, collection, image, and technical data needed to host and operate our servers, databases, and recognition services.</td>
</tr>
</tbody></table>
<p>Advertising attribution integrations may send relevant identifiers and conversion events to the advertising platforms connected to those campaigns. The information involved depends on the enabled integration and applicable permissions. This does not authorize disclosure of scan images or collection contents for advertising.</p>
<p>Service providers processing data on our behalf are distinct from independent services you choose to visit or use. Transfers to a processor may still be described in this policy even where they are exempt from the specific “sharing” label in Google Play&#39;s Data safety form.</p>
<p>Provider privacy information:</p>
<ul>
<li><p><a href="https://policies.google.com/privacy">Google Privacy Policy</a></p>
</li>
<li><p><a href="https://firebase.google.com/support/privacy">Firebase Privacy and Security</a></p>
</li>
<li><p><a href="https://mixpanel.com/legal/privacy-policy/">Mixpanel Privacy Policy</a></p>
</li>
<li><p><a href="https://www.singular.net/privacy-policy/">Singular Privacy Policy</a></p>
</li>
<li><p><a href="https://www.apple.com/legal/privacy/">Apple Privacy Policy</a></p>
</li>
</ul>
<p>We may also disclose information when legally required, to address security incidents or protect legal rights, or in connection with a business transfer subject to applicable privacy obligations. If you choose to share content through another app or open an external marketplace, the recipient&#39;s own practices apply.</p>
<p>We do not sell personal information for money. Where applicable law treats advertising-related disclosure as “sharing,” a “sale,” or targeted advertising, you may exercise the applicable rights by contacting us.</p>
<h2>5. Retention and Deletion</h2>
<h3>Records on our servers</h3>
<p>We retain your platform account, collection records, uploaded scan images, and scan records to provide the Service until you delete that platform account or delete individual records through an available feature.</p>
<p><strong>When a verified account deletion is executed, the account and its associated information on our own servers are deleted immediately, without a scheduled waiting period. We do not retain those deleted account records on our servers for later account recovery.</strong> The immediate deletion statement concerns execution of the deletion operation; an emailed request may first require support review and identity verification.</p>
<h3>Records held by third parties</h3>
<p><strong>Deleting your CardScanFox account does not automatically or immediately erase records already held in Firebase, Mixpanel, Singular, Apple, or other third-party systems.</strong> Analytics, attribution, and diagnostic records in those systems are subject to the relevant service&#39;s retention settings, deletion mechanisms, and applicable legal requirements. We do not represent that these records disappear at the same time as our server records.</p>
<p>For requests concerning personal information held by providers in connection with CardScanFox, contact us at <a href="mailto:support@tcgcard.fun">support@tcgcard.fun</a>. We handle requests according to applicable rights and available provider procedures. Independent provider accounts, such as your Google or Apple account, must be managed through the provider. Apple&#39;s transaction records are governed by Apple&#39;s own obligations and policies.</p>
<p>Support correspondence and deletion-request communications are separate from your in-app collection records and may remain in the systems used to handle your request for as long as necessary to resolve it and meet applicable legal obligations. If a legal requirement prevents deletion of particular information, we will explain the applicable reason and scope where permitted.</p>
<h2>6. How to Delete Your Account</h2>
<p>You can initiate deletion through <strong>Delete Account</strong> in the app&#39;s account settings. You can also use our <a href="https://tcgcard.fun/Account/AccountSetup">account deletion webpage</a> without reinstalling the app, or email <a href="mailto:support@tcgcard.fun">support@tcgcard.fun</a>.</p>
<p>Specify <strong>Android or iOS</strong> and identify the account you want deleted. If the webpage opens an email draft, you must send that email to submit the request. We may need to verify that the request comes from the account holder. Do not send passwords or verification codes. For guest data, contact support so we can help identify the relevant records.</p>
<p>Deletion removes the selected platform account and its associated server records, including collections, Wishlist, folders, saved card details, scan images and records, and preferences, and ends access through that platform account&#39;s sessions. <strong>To use an account on that platform again, you must register again. Signing in with the same email or Google account does not recover deleted data.</strong></p>
<p>The separate account and records on the other platform remain unaffected. If you want both deleted, request deletion for both platforms. Deletion does not delete your Apple or Google account.</p>
<p>Deleting CardScanFox or its iOS account <strong>does not cancel an Apple subscription</strong>. Manage or cancel that subscription in your Apple account&#39;s subscription settings. Canceling a subscription is not a prerequisite for submitting a CardScanFox account-deletion request. Uninstalling the app alone does not delete a server-side account.</p>
<h2>7. Your Rights and Choices</h2>
<p>Depending on your location, you may have rights to access, correct, delete, obtain a copy of, restrict, or object to processing of your personal information; withdraw consent; or opt out of applicable targeted advertising or sharing. You may also complain to the relevant data protection authority. Contact <a href="mailto:support@tcgcard.fun">support@tcgcard.fun</a> to exercise applicable rights. We may request proportionate verification to protect your information.</p>
<p>You can manage camera and photo permissions in device settings. You can manage available advertising-identifier controls on Android and tracking permissions on iOS. These controls do not necessarily stop all analytics, diagnostics, or information needed to operate your account. We do not imply that every data category has an in-app opt-out switch.</p>
<h2>8. Security and International Processing</h2>
<p>We use reasonable technical and organizational measures designed to protect information against unauthorized access, misuse, loss, and disclosure. Our production app-to-API connection uses HTTPS. No method of electronic transmission or storage is completely secure, and we cannot guarantee absolute security.</p>
<p>Information may be processed in countries where our infrastructure and service providers operate. Their laws may differ from those where you live. Applicable transfer and data-protection requirements continue to apply to such processing.</p>
<h2>9. Children&#39;s Privacy</h2>
<p>CardScanFox is intended for users aged <strong>13 and older</strong> and is not directed to children under 13. Where applicable law requires a higher age or parental authorization, that requirement applies. Users below the age of majority need a parent or guardian&#39;s permission to use the Service.</p>
<p>If you believe a child has provided personal information contrary to these requirements, contact us so we can investigate and delete it as appropriate. Store content ratings describe content suitability and do not replace these eligibility requirements.</p>
<h2>10. Changes and Contact</h2>
<p>We may update this policy as the Service or our practices change. The version date identifies the revision; it takes effect when published on our website unless a later effective date is stated. We provide notice of material changes where required by law and obtain consent where legally required.</p>
<p>Privacy contact: <a href="mailto:support@tcgcard.fun">support@tcgcard.fun</a>   Website: <a href="https://tcgcard.fun">https://tcgcard.fun</a>   Privacy Policy: <a href="https://tcgcard.fun/privacy">https://tcgcard.fun/privacy</a>   Terms of Use: <a href="https://tcgcard.fun/terms">https://tcgcard.fun/terms</a>   Account deletion: <a href="https://tcgcard.fun/Account/AccountSetup">https://tcgcard.fun/Account/AccountSetup</a></p>
`;
}

function supportContent(): string {
  return `
    <p>Get help with ${PRODUCT_NAME} scanning, account access, collection data, and app settings.</p>
    <h2>Contact support</h2>
    <p>Open Profile in the app and select Customer Support to send a request with the relevant category and details. You may also email <a href="mailto:kando@tcgcard.fun">kando@tcgcard.fun</a>.</p>
    <p>Do not send passwords, verification codes, or payment information in a support request.</p>
    <h2>Account deletion</h2>
    <p>You can delete your account from Profile &gt; Account &gt; Delete account. This deletes the account and associated business data on the current platform only. If you cannot access the app, contact support from the email address associated with your account and specify Android or iOS. Do not provide your password. Identity and platform verification are required before processing; an email request is not confirmation that deletion is complete.</p>
    <p>Android deletion instructions and email requests are available at <a href="https://tcgcard.fun/Account/AccountSetup">Account Setup</a>.</p>
    <h2>Policies</h2>
    <p>Review the <a href="/api/v1/legal/terms">Terms of Use</a> and <a href="/api/v1/legal/privacy">Privacy Policy</a> for service and data-handling details.</p>`;
}
