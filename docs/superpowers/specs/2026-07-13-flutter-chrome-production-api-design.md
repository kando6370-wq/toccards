# Flutter Chrome Production API Testing Design

## Goal

Run the Flutter application locally in Chrome on a stable origin while all application data flows through the production Workers API and its production D1/KV bindings.

## Design

- Use `http://localhost:3000` as the fixed Flutter Web development origin.
- Pass `https://api.tcgcard.fun/api/v1` through `KANDO_API_BASE_URL` with `--dart-define`.
- Centralize the Dart environment value in one shared API configuration file.
- Keep the existing local Worker URL as the default for ordinary development and tests.
- Add the exact localhost origin to the Worker CORS allowlist alongside the production admin domain.
- Provide a repository script so the production-connected Chrome session starts with one command.

## Security Boundary

The browser never connects directly to D1 or KV. It connects only to the production Worker API, which retains control of database bindings, authentication, and authorization.
