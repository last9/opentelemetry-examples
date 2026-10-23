# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies for SQLite
RUN apk add --no-cache gcc musl-dev

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build with CGO enabled for SQLite
RUN CGO_ENABLED=1 GOOS=linux go build -o /app/server .

# Runtime stage
FROM alpine:3.22

# --upgrade pulls the CA bundle newer than the base image ships
RUN apk add --no-cache --upgrade ca-certificates ca-certificates-bundle

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/server /app/server

# Expose port
EXPOSE 8080

# Run the binary
CMD ["/app/server"]
