# Linux dev Apple callback origin isolation

The public `111.10.170.43:8089` NAT still targets `192.168.50.201:8080`.
On the Linux host, `toccards-callback-redirect.service` installs a separate IPv4
`nftables` prerouting table at priority -101, before Docker's -100 DNAT. Only
connections to `192.168.50.201:8080` arriving on `ens160` from outside the
RFC1918 private ranges are redirected to port 8081. Private clients continue
to reach the existing Web/Admin/API on 8080 without any Compose changes.

`toccards-callback-gateway.service` runs `callback-gateway.mjs` on 8081. It
accepts only the exact `POST /api/v1/apple/notifications/v2/sandbox` path,
limits the body to 200,000 bytes, strips caller credentials and forwards to
`http://127.0.0.1:8080`. It does not validate Apple signatures or store
notifications; the existing Linux API does both. Other paths return 404 and
other methods return 405. The origin hop remains HTTP; Cloudflare's HTTPS
edge does not encrypt this leg.

The first installation on kd201 copies the gateway to
`/home/user/apps/toccards-test/shared/callback-gateway.mjs`, the two unit
files to `/etc/systemd/system/toccards-callback-{gateway,redirect}.service`,
and the policy to `/etc/toccards-callback-redirect.nft`. Both services are
enabled at boot. The gateway must start before the redirect rule. The rule
is confined to the `ip toccards_callback` table; no Docker or other project
table is modified. Check syntax with `sudo nft -c -f callback-redirect.nft`
and behavior with `node --test callback-gateway.test.mjs` before installing
an update. Changes to this repository do not automatically replace the
host's shared gateway file or units; synchronize them explicitly.

After any router, interface, address, Docker or firewall change, repeat the
external and private checks:

- From a genuine public source, `/`, `/api/v1/health` and Admin paths return
  404 even if the `Host` header claims `192.168.50.201:8080`. The exact
  callback GET returns 405 and an empty JSON POST reaches Linux as 400.
- From the private network, `http://192.168.50.201:8080/` and `/api/v1/health`
  continue to return the Admin page and 200 respectively.
- Through `https://dev-callback.tcgcard.fun`, the callback still reaches
  Linux. A replay of the same signed Apple TEST should remain idempotent.

On 2026-09-17 after installation, one new official Apple Sandbox TEST had a
`SUCCESS` delivery result and a matching, processed Linux inbox UUID and
payload digest. No purchase transaction was created by the TEST.

The rule trusts RFC1918 sources. During installation, packet capture showed
the public NAT retaining public source addresses and the internal client
arriving from a private address. A LAN HTTP proxy can itself route a request
to the private service; its access control remains a separate boundary. If
the router begins source-NATing public traffic to a private address, this
rule will no longer isolate that traffic. This host has no globally routed
IPv6 address; add an IPv6 policy before exposing one.

If the gateway fails, leave the redirect rule active so the public origin
fails closed, then repair or restart `toccards-callback-gateway.service`.
Stopping `toccards-callback-redirect.service` deletes only its own nftables
table but **re-exposes the entire 8080 site through the existing NAT**; use
that rollback only as an explicit emergency decision. The Apple callback
Worker, CF recognition service and production deployment are independent.
