# Multi-stage build for Go application
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Install ca-certificates for HTTPS
RUN apk add --no-cache ca-certificates

# Copy go mod files
COPY go.mod go.sum* ./

# Download dependencies
RUN go mod download

# Copy source code
COPY *.go ./

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o server .

# Production stage
FROM alpine:3.19

WORKDIR /app

# Install ca-certificates for HTTPS
RUN apk add --no-cache ca-certificates

# Copy the binary
COPY --from=builder /app/server .

# Cloud Run expects PORT environment variable
ENV PORT=8080
EXPOSE 8080

# Run the server
CMD ["./server"]
