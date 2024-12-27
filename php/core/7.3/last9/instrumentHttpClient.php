<?php
namespace Last9;

use GuzzleHttp\Client;

class InstrumentedHttpClient {
    private $client;

    public function __construct(array $config = []) {
        $this->client = new Client($config);
    }

    public function request($method, $uri, array $options = []) {
        $spanData = \Last9\createSpan(
            'http.client',
            \Last9\Instrumentation::getRootSpanId(),
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
            \Last9\endSpan($spanData, 
                ['code' => 1],
                [
                    ['key' => 'http.status_code', 'value' => ['intValue' => $response->getStatusCode()]],
                    ['key' => 'http.response.body.size', 'value' => ['intValue' => strlen($response->getBody())]]
                ]
            );
            return $response;
        } catch (\Exception $e) {
            \Last9\endSpan($spanData, 
                ['code' => 2, 'message' => $e->getMessage()],
                [['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]]]
            );
            throw $e;
        }
    }
}