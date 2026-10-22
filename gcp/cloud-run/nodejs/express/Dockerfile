# Multi-stage build for smaller image
FROM node:24.22.1-slim@sha256:1681862882da07ee5476fee047bcf34138833f1df42633bb25bcb0f438d5bf3d AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install all dependencies (including dev)
RUN npm ci

# Production stage
FROM node:24.22.1-slim@sha256:1681862882da07ee5476fee047bcf34138833f1df42633bb25bcb0f438d5bf3d

WORKDIR /app

# Copy node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application files
COPY package*.json ./
COPY instrumentation.js ./
COPY app.js ./

# Cloud Run expects PORT environment variable
ENV PORT=8080
ENV NODE_ENV=production

EXPOSE 8080

# Run with instrumentation loaded first
CMD ["node", "-r", "./instrumentation.js", "app.js"]
