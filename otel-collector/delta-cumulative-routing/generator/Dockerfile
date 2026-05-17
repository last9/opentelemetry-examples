FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY main.go .
RUN CGO_ENABLED=0 go build -o generator .

FROM alpine:3.20
COPY --from=builder /app/generator /generator
ENTRYPOINT ["/generator"]
