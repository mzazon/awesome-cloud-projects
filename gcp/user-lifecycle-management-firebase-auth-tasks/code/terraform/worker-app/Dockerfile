# Multi-stage Dockerfile for User Lifecycle Worker Service
# Optimized for Cloud Run deployment with security and performance best practices

# Build stage
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Install build dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

# Copy package files
COPY package*.json ./

# Install production dependencies
RUN npm ci --only=production --no-audit --no-fund

# Production stage
FROM node:18-alpine AS production

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S node -u 1001 -G nodejs

# Set working directory
WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    dumb-init

# Copy application code and dependencies
COPY --from=builder --chown=node:nodejs /app/node_modules ./node_modules
COPY --chown=node:nodejs package*.json ./
COPY --chown=node:nodejs index.js ./

# Set environment variables for production
ENV NODE_ENV=production
ENV NPM_CONFIG_UPDATE_NOTIFIER=false
ENV NPM_CONFIG_FUND=false
ENV NPM_CONFIG_AUDIT_LEVEL=critical

# Switch to non-root user
USER node

# Expose port (Cloud Run will set PORT environment variable)
EXPOSE 8080

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD node -e "const http = require('http'); \
    const options = { hostname: 'localhost', port: process.env.PORT || 8080, path: '/health', timeout: 5000 }; \
    const req = http.request(options, (res) => process.exit(res.statusCode === 200 ? 0 : 1)); \
    req.on('error', () => process.exit(1)); \
    req.end();"

# Use dumb-init for proper signal handling
ENTRYPOINT ["dumb-init", "--"]

# Start the application
CMD ["node", "index.js"]

# Labels for metadata and tracking
LABEL maintainer="User Lifecycle Management System" \
      description="Cloud Run worker service for processing user lifecycle events" \
      version="1.0.0" \
      org.opencontainers.image.title="User Lifecycle Worker" \
      org.opencontainers.image.description="Processes Firebase authentication events and manages user lifecycle automation" \
      org.opencontainers.image.vendor="Google Cloud Recipe" \
      org.opencontainers.image.source="https://github.com/your-org/user-lifecycle-management"