<?php
namespace Last9;

class InstrumentedMySQLi extends \mysqli {
    public function query($query, $resultmode = MYSQLI_STORE_RESULT) {
        $spanData = createSpan(
            'database.query',
            Instrumentation::getRootSpanId(),
            [
                ['key' => 'db.system', 'value' => ['stringValue' => 'mysql']],
                ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
                ['key' => 'db.type', 'value' => ['stringValue' => 'sql']],
                ['key' => 'db.operation', 'value' => ['stringValue' => 'query']]
            ]
        );

        try {
            $result = parent::query($query, $resultmode);
            if ($result === false) {
                endSpan($spanData, 
                    ['code' => 2, 'message' => $this->error],
                    [
                        ['key' => 'error.message', 'value' => ['stringValue' => $this->error]],
                        ['key' => 'error.code', 'value' => ['intValue' => $this->errno]]
                    ]
                );
            } else {
                endSpan($spanData, ['code' => 1]);
            }
            return $result;
        } catch (\Exception $e) {
            endSpan($spanData, 
                ['code' => 2, 'message' => $e->getMessage()],
                [
                    ['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]],
                    ['key' => 'error.code', 'value' => ['intValue' => $e->getCode()]]
                ]
            );
            throw $e;
        }
    }

    public function prepare($query) {
        $spanData = createSpan(
            'database.query',
            Instrumentation::getRootSpanId(),
            [
                ['key' => 'db.system', 'value' => ['stringValue' => 'mysql']],
                ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
                ['key' => 'db.type', 'value' => ['stringValue' => 'sql']],
                ['key' => 'db.operation', 'value' => ['stringValue' => 'prepare']]
            ]
        );

        $stmt = parent::prepare($query);
        
        if ($stmt === false) {
            endSpan($spanData, 
                ['code' => 2, 'message' => $this->error],
                [
                    ['key' => 'error.message', 'value' => ['stringValue' => $this->error]],
                    ['key' => 'error.code', 'value' => ['intValue' => $this->errno]]
                ]
            );
            return false;
        }
        
        endSpan($spanData, ['code' => 1]);
        return new InstrumentedMySQLiStatement($stmt, $query);
    }
}

class InstrumentedMySQLiStatement {
    private $stmt;
    private $query;

    public function __construct($stmt, $query) {
        $this->stmt = $stmt;
        $this->query = $query;
    }

    public function bind_param($types, &...$vars) {
        return $this->stmt->bind_param($types, ...$vars);
    }

    public function execute() {
        $spanData = createSpan(
            'database.query',
            Instrumentation::getRootSpanId(),
            [
                ['key' => 'db.system', 'value' => ['stringValue' => 'mysql']],
                ['key' => 'db.statement', 'value' => ['stringValue' => $this->query]],
                ['key' => 'db.type', 'value' => ['stringValue' => 'sql']],
                ['key' => 'db.operation', 'value' => ['stringValue' => 'execute']]
            ]
        );

        try {
            $result = $this->stmt->execute();
            // In the query method when there's an error:
            if ($result === false) {
                endSpan($spanData, 
                    ['code' => 2, 'message' => $this->error],
                    [
                        ['key' => 'error.message', 'value' => ['stringValue' => $this->error]],
                        ['key' => 'error.code', 'value' => ['intValue' => $this->errno]]
                    ],
                    [ // Add events array for error
                        [
                            'name' => 'exception',
                            'timeUnixNano' => (int)(microtime(true) * 1e9),
                            'attributes' => [
                                ['key' => 'exception.type', 'value' => ['stringValue' => 'MySQLError']],
                                    ['key' => 'exception.message', 'value' => ['stringValue' => $this->error]],
                                ['key' => 'exception.code', 'value' => ['intValue' => $this->errno]]
                            ]
                        ]
                    ]
                );
            } else {
                endSpan($spanData, ['code' => 1]);
            }
            return $result;
        } catch (\Exception $e) {
            endSpan($spanData, 
                ['code' => 2, 'message' => $e->getMessage()],
                [
                    ['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]],
                    ['key' => 'error.code', 'value' => ['intValue' => $e->getCode()]]
                ],
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

    public function get_result() {
        return $this->stmt->get_result();
    }

    public function close() {
        return $this->stmt->close();
    }

    public function __get($name) {
        return $this->stmt->$name;
    }

    public function __call($name, $arguments) {
        return call_user_func_array([$this->stmt, $name], $arguments);
    }
}