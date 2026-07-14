import { describe, expect, it } from "vitest";
import app from "../index";

// 意图：跨域预检（OPTIONS）必须由 CORS 中间件短路处理，绝不能落到 requireAdmin 上。
// WHY：浏览器发预检时不会携带 Authorization，如果预检返回 401，则任何跨域后台请求
// （含登录）都会被浏览器判为 CORS error —— 这正是线上 admin.tcgcard.fun 登录失败的根因。
describe("admin API CORS preflight", () => {
  it("answers OPTIONS preflight with 204 + ACAO for an allowlisted origin, not 401 from admin auth", async () => {
    const res = await app.request(
      "/api/v1/admin/auth/login",
      {
        method: "OPTIONS",
        headers: {
          Origin: "https://admin.tcgcard.fun",
          "Access-Control-Request-Method": "POST",
          "Access-Control-Request-Headers": "authorization,content-type",
        },
      },
      { JWT_SECRET: "test-secret" } as unknown as Parameters<typeof app.request>[2],
    );

    expect(res.status).toBe(204);
    expect(res.headers.get("access-control-allow-origin")).toBe(
      "https://admin.tcgcard.fun",
    );
  });
});
