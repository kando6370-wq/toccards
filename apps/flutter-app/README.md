# Kando App

## Environments

`APP_ENV` selects the API and Mixpanel projects together. The supported values
are `test` and `production`; the default is `test`.

From the repository root, run the web app with:

```bash
pnpm app:chrome:dev
pnpm app:chrome:prod
```

Build a TestFlight package against test services with:

```bash
flutter build ipa --release --dart-define-from-file=config/test.json
```

Build an App Store package against production services with:

```bash
flutter build ipa --release --dart-define-from-file=config/production.json
```

Run these `flutter build` commands from `apps/flutter-app`.

## Chrome with production services

From the repository root, run:

```bash
pnpm app:chrome:prod
```

This starts Flutter Web at `http://localhost:3000` and configures every app API client to use:

```text
https://api.tcgcard.fun/api/v1
```

The browser does not connect directly to D1 or KV. Production data access remains behind the deployed Worker API, including its authentication and authorization checks.
