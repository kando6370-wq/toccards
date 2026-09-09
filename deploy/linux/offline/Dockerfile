ARG NODE_RUNTIME_IMAGE=toccards-node-runtime:22

FROM ${NODE_RUNTIME_IMAGE} AS api

ENV NODE_ENV=production
WORKDIR /app
COPY apps/workers-api/dist/linux/server.mjs ./server.mjs
COPY apps/workers-api/dist/linux/server.mjs.map ./server.mjs.map

EXPOSE 3000
CMD ["node", "--enable-source-maps", "/app/server.mjs"]

FROM ${NODE_RUNTIME_IMAGE} AS web

ENV NODE_ENV=production
WORKDIR /app
COPY deploy/linux/offline/web-server.mjs ./web-server.mjs
COPY apps/admin-web/dist /srv

EXPOSE 80
CMD ["node", "/app/web-server.mjs"]
