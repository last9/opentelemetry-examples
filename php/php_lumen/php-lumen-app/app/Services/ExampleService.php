<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Database\Eloquent\ModelNotFoundException;

/**
 * Example Service demonstrating OpenTelemetry Error Service usage
 */
class ExampleService
{
    protected OpenTelemetryErrorService $errorService;

    public function __construct(OpenTelemetryErrorService $errorService)
    {
        $this->errorService = $errorService;
    }

    /**
     * Example of using the error service for a business operation
     */
    public function performOperation()
    {
        return $this->errorService->traceOperation('my.service.operation', function () {
            // Your operation code
            $this->errorService->addErrorAttributes([
                'operation.type' => 'business_logic',
                'operation.complexity' => 'high',
            ]);
            
            // Simulate some work
            usleep(100000); // 100ms
            
            return [
                'status' => 'success',
                'message' => 'Operation completed successfully',
                'timestamp' => now()->toISOString()
            ];
        });
    }

    /**
     * Example of database error tracing
     */
    public function getUser($id)
    {
        return $this->errorService->traceDatabaseQuery(
            'SELECT * FROM users WHERE id = ?',
            [$id],
            function () use ($id) {
                // Database operation
                $user = User::find($id);
                if (!$user) {
                    throw new ModelNotFoundException('User not found');
                }
                return $user;
            }
        );
    }

    /**
     * Example of external API error tracing
     */
    public function callExternalApi()
    {
        return $this->errorService->traceExternalApiCall(
            'https://api.example.com/data',
            'GET',
            function () {
                $client = new \GuzzleHttp\Client();
                $response = $client->get('https://api.example.com/data');
                return $response;
            }
        );
    }

    /**
     * Example of custom error recording
     */
    public function recordCustomError($userId, $paymentId, $amount)
    {
        // Record custom error attributes
        $this->errorService->addErrorAttributes([
            'error.category' => 'business_logic',
            'error.severity' => 'high',
            'user.id' => $userId,
        ]);

        // Record custom error event
        $this->errorService->recordErrorEvent('payment.failed', [
            'payment.id' => $paymentId,
            'amount' => $amount,
            'reason' => 'insufficient_funds',
        ]);
    }

    /**
     * Example of file operation tracing
     */
    public function processFile($filePath)
    {
        return $this->errorService->traceFileOperation(
            'read',
            $filePath,
            function () use ($filePath) {
                if (!file_exists($filePath)) {
                    throw new \Exception("File not found: {$filePath}");
                }
                
                $content = file_get_contents($filePath);
                return [
                    'file_path' => $filePath,
                    'size' => strlen($content),
                    'processed' => true
                ];
            }
        );
    }

    /**
     * Example of email operation tracing
     */
    public function sendEmail($recipient, $subject)
    {
        return $this->errorService->traceEmailOperation(
            'send',
            $recipient,
            function () use ($recipient, $subject) {
                // Simulate email sending
                usleep(50000); // 50ms
                
                if (empty($recipient)) {
                    throw new \InvalidArgumentException('Recipient email is required');
                }
                
                return [
                    'recipient' => $recipient,
                    'subject' => $subject,
                    'sent' => true,
                    'timestamp' => now()->toISOString()
                ];
            }
        );
    }
}
