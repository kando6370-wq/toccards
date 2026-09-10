ARG NODE_IMAGE=node:22-bookworm-slim
ARG CADDY_IMAGE=caddy:2-alpine

FROM ${NODE_IMAGE} AS build

WORKDIR /workspace
RUN corepack enable

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json tsconfig.base.json ./
COPY packages ./packages
COPY apps/admin-web ./apps/admin-web
COPY apps/marketing-web ./apps/marketing-web
COPY apps/workers-api ./apps/workers-api

RUN pnpm install --frozen-lockfile
RUN pnpm --filter @kando/workers-api build:linux

FROM ${NODE_IMAGE} AS api

ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /workspace/apps/workers-api/dist/linux/server.mjs ./server.mjs
COPY --from=build /workspace/apps/workers-api/dist/linux/server.mjs.map ./server.mjs.map

USER node
EXPOSE 3000
CMD ["node", "--enable-source-maps", "/app/server.mjs"]

FROM ${CADDY_IMAGE} AS web

COPY deploy/linux/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /workspace/apps/admin-web/dist /srv

EXPOSE 80 443
