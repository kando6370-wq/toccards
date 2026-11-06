ARG NODE_IMAGE=node:22.23.4-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da
ARG CADDY_IMAGE=caddy:2.11.8-alpine@sha256:3db3a09e418f86a8fce8de4bc0026fccd2b4cd925aef00cc7d843d9fdc75e442

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
