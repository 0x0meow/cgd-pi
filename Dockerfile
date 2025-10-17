# CoreGeek Displays Raspberry Pi Kiosk Integration
# Multi-stage Dockerfile for ARM64 Raspberry Pi 4/5
# Reference: docs/server-api-events.md section 8.4

FROM node:20-alpine AS deps
WORKDIR /app

# Install production dependencies only
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

# Production stage - minimal runtime image
FROM node:20-alpine

WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy application source
COPY . .

# Non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

USER nodejs

# Environment configuration
ENV NODE_ENV=production \
    PORT=3000

# Health check endpoint for monitoring (section 8.8)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/healthz', (r) => { process.exit(r.statusCode === 200 ? 0 : 1); })"

EXPOSE 3000

# Start the signage server
CMD ["node", "server.js"]
