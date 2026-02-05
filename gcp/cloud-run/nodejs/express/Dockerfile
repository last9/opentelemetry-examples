# Multi-stage build for smaller image
FROM node:20-slim AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install all dependencies (including dev)
RUN npm ci

# Production stage
FROM node:20-slim

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
