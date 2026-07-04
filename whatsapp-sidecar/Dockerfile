# azulzin WhatsApp sidecar — Debian-slim + system Chromium.
# Debian is preferred over Alpine (musl Chromium is finicky).
FROM node:22-bookworm-slim

# System Chromium + fonts. Skip puppeteer's ~800MB bundled download.
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium ca-certificates fonts-liberation \
 && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

# Session lives on a persistent volume so redeploys don't force a re-QR.
# Mount a named/persistent volume here.
VOLUME ["/app/.wwebjs_auth"]

USER node

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s CMD \
  node -e "require('http').get('http://localhost:3001/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

# --max-old-space-size caps heap growth (OOM is the classic crash).
CMD ["node", "--max-old-space-size=1024", "server.js"]
