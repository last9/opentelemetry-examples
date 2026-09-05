.PHONY: build build-EnrichmentFunction test test-coverage clean package

build:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o bootstrap .
	chmod +x bootstrap

build-EnrichmentFunction:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o $(ARTIFACTS_DIR)/bootstrap .
	chmod +x $(ARTIFACTS_DIR)/bootstrap

test:
	go test -v -race ./...

test-coverage:
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html

clean:
	rm -f bootstrap coverage.out coverage.html

deploy: build
	sam deploy --guided

package: build
	zip bootstrap.zip bootstrap
