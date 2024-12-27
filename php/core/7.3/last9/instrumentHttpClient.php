<?php
namespace Last9;

use GuzzleHttp\Client;

class InstrumentedHttpClient {
    private $client;

    public function __construct(array $config = []) {
        $this->client = new Client($config);
    }

    public function request($method, $uri, array $options = []) {
        $spanData = createSpan(
            'http.client',
            Instrumentation::getRootSpanId(),
            [
                ['key' => 'http.method', 'value' => ['stringValue' => $method]],
                ['key' => 'http.url', 'value' => ['stringValue' => $uri]],
                ['key' => 'http.flavor', 'value' => ['stringValue' => '1.1']],
                ['key' => 'network.protocol.name', 'value' => ['stringValue' => 'http']],
                ['key' => 'network.protocol.version', 'value' => ['stringValue' => '1.1']]
            ]
        );

        try {
            $response = $this->client->request($method, $uri, $options);
            endSpan($spanData, 
                ['code' => 1],
                [
                    ['key' => 'http.status_code', 'value' => ['intValue' => (int)$response->getStatusCode()]],
                    ['key' => 'http.response.body.size', 'value' => ['intValue' => (int)strlen($response->getBody())]]
                ]
            );
            return $response;
        } catch (\Exception $e) {
            endSpan($spanData, 
                ['code' => 2, 'message' => $e->getMessage()],
                [['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]]],
                [ // Add events array for error
                    [
                        'name' => 'exception',
                        'timeUnixNano' => (int)(microtime(true) * 1e9),
                        'attributes' => [
                            ['key' => 'exception.type', 'value' => ['stringValue' => get_class($e)]],
                            ['key' => 'exception.message', 'value' => ['stringValue' => $e->getMessage()]],
                            ['key' => 'exception.stacktrace', 'value' => ['stringValue' => $e->getTraceAsString()]]
                        ]
                    ]
                ]
            );
            throw $e;
        }
    }
}