# azulzin WhatsApp sidecar — Debian-slim + Google Chrome stable.
# We install Google Chrome (not Debian's apt `chromium`): the Debian chromium binary crashes
# headless in a container (SIGILL on launch, regardless of flags), whereas Chrome stable is the
# browser whatsapp-web.js/puppeteer are tested against. apt resolves Chrome's full runtime
# dependency graph for us, so no hand-maintained shared-library list.
FROM node:22-bookworm-slim

# Google Chrome stable + fonts. The signing key + apt source pull Chrome and all its libs.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates fonts-liberation wget gnupg \
 && wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
 && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
      > /etc/apt/sources.list.d/google-chrome.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends google-chrome-stable \
 && rm -rf /var/lib/apt/lists/*

# Skip puppeteer's ~800MB bundled download; drive the system Chrome we just installed.
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/google-chrome-stable

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

# Pre-create the LocalAuth session dir owned by the non-root `node` user. A fresh named volume
# mounted here inherits this ownership, so the WhatsApp session persists across redeploys with
# no manual chown (otherwise a new volume is root-owned and the client can't write it).
RUN mkdir -p /app/.wwebjs_auth && chown -R node:node /app/.wwebjs_auth

# Session lives on a persistent volume so redeploys don't force a re-QR.
# Mount a named/persistent volume here.
VOLUME ["/app/.wwebjs_auth"]

USER node

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s CMD \
  node -e "require('http').get('http://localhost:3001/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

# --max-old-space-size caps heap growth (OOM is the classic crash).
CMD ["node", "--max-old-space-size=1024", "server.js"]
