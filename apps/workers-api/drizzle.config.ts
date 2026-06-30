import { defineConfig } from "drizzle-kit";

// 仅用于 `drizzle-kit generate` 产出迁移 SQL；运行期由 wrangler d1 绑定，无需 dbCredentials。
export default defineConfig({
  dialect: "sqlite",
  schema: "./src/db/schema.ts",
  out: "./src/db/migrations",
});
