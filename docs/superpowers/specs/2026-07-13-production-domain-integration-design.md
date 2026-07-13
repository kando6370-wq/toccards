# Production Domain Integration Design

## Goal

Connect the deployed admin console at `https://admin.tcgcard.fun` to the Workers API at `https://api.tcgcard.fun` without breaking local Vite development.

## Design

- The admin console reads `VITE_API_BASE_URL` when provided.
- Production builds default to `https://api.tcgcard.fun/api/v1/admin`.
- Vite development defaults to `/api/v1/admin`, preserving the existing local/demo behavior.
- The Worker uses Hono CORS middleware for `/api/*` and allows only `https://admin.tcgcard.fun` for browser cross-origin requests.
- CORS permits `Authorization` and `Content-Type`, plus the methods used by the admin console.

## Verification

- Static verification covers production and development API base selection without adding a new admin test dependency.
- Worker tests cover allowed-origin preflight behavior and rejection of an unrelated origin.
- Admin and Worker production builds complete successfully.
