# Node 10 Express with OpenTelemetry Example
FROM node:10-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application code
COPY . .

# Expose port
EXPOSE 3000

# Start with instrumentation
CMD ["node", "-r", "./instrumentation.js", "app.js"]
