# Builds inside a context that includes both go-agent and l9_otel_examples,
# so the local replace directive in go.mod resolves at build time.
#
# Compose passes context: ../../.. → ~/Projects (the parent of both repos).
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go-agent/ /src/go-agent/
COPY l9_otel_examples/go/gorm/ /src/l9_otel_examples/go/gorm/
WORKDIR /src/l9_otel_examples/go/gorm
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/app .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=build /out/app /usr/local/bin/app
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/app"]
