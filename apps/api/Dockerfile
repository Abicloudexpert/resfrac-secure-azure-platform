# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# Multi-stage build. The runtime image contains only production dependencies
# and runs as a non-root user (defence in depth). Suitable for App Service
# (container) or Container Apps; the plain zip-deploy path is also supported.
# ---------------------------------------------------------------------------
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
# Non-root user (node) already exists in the base image.
COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node package*.json ./
COPY --chown=node:node src ./src
USER node
EXPOSE 8080
# Container-level health check hitting the liveness endpoint.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PORT||8080)+'/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"
CMD ["node", "src/server.js"]
