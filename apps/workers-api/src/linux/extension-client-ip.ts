import { isIP } from "node:net";

export function extensionClientIp(
  request: Request,
  remoteAddress: string | undefined,
  trustProxy: boolean,
): string | undefined {
  const forwarded = trustProxy
    ? request.headers.get("X-Forwarded-For")?.split(",").at(-1)?.trim()
    : undefined;
  const address = forwarded && isIP(forwarded) ? forwarded : remoteAddress;
  if (!address || !isIP(address)) return undefined;
  return address.startsWith("::ffff:") && isIP(address.slice(7)) === 4
    ? address.slice(7)
    : address;
}
