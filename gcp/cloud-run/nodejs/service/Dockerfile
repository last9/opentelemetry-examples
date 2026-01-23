FROM node:20-slim

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Cloud Run uses PORT env var
ENV PORT=8080

EXPOSE 8080

CMD ["node", "index.js"]
