<?php
namespace Last9;

class DB {
    private static $instance = null;

    public static function connect($dsn, $username = null, $password = null, array $options = []) {
        if (self::$instance === null) {
            self::$instance = new InstrumentedPDO($dsn, $username, $password, $options);
        }
        return self::$instance;
    }
}

class InstrumentedPDO extends \PDO {
    private $dsn;
    private $username;
    private $password;
    private $options;

    public function __construct($dsn, $username = null, $password = null, array $options = []) {
        $this->dsn = $dsn;
        $this->username = $username;
        $this->password = $password;
        $this->options = $options;
        parent::__construct($dsn, $username, $password, array_merge([
            \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION
        ], $options));
    }

    public function prepare($query, $options = []) {
        try {
            $stmt = parent::prepare($query, $options);
            return new InstrumentedPDOStatement($stmt, $query);
        } catch (\PDOException $e) {
            // Create and end span here for prepare errors
            $spanData = \Last9\createSpan(
                'database.query',
                \Last9\Instrumentation::getRootSpanId(),
                [
                    ['key' => 'db.system', 'value' => ['stringValue' => 'mariadb']],
                    ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
                    ['key' => 'db.type', 'value' => ['stringValue' => 'sql']],
                    ['key' => 'db.operation', 'value' => ['stringValue' => 'prepare']]
                ]
            );
            \Last9\endSpan($spanData, 
                ['code' => 2, 'message' => $e->getMessage()],
                [
                    ['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]],
                    ['key' => 'error.code', 'value' => ['stringValue' => $e->getCode()]],
                    ['key' => 'error.type', 'value' => ['stringValue' => get_class($e)]]
                ]
            );
            throw $e;
        }
    }

    public function query(string $query, ?int $fetchMode = null, ...$fetchModeArgs) {
        $spanData = \Last9\createSpan(
            'database.query',
            \Last9\Instrumentation::getRootSpanId(),
            [
                ['key' => 'db.system', 'value' => ['stringValue' => 'mariadb']],
                ['key' => 'db.statement', 'value' => ['stringValue' => $query]],
                ['key' => 'db.type', 'value' => ['stringValue' => 'sql']],
                ['key' => 'db.operation', 'value' => ['stringValue' => 'query']]
            ]
        );

        try {
            $result = parent::query($query, $fetchMode, ...$fetchModeArgs);
            \Last9\endSpan($spanData, ['code' => 1]);
            return $result;
        } catch (\PDOException $e) {
            \Last9\endSpan($spanData, 
                ['code' => 2, 'message' => $e->getMessage()],
                [
                    ['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]],
                    ['key' => 'error.code', 'value' => ['stringValue' => $e->getCode()]],
                    ['key' => 'error.type', 'value' => ['stringValue' => get_class($e)]]
                ]
            );
            throw $e;
        }
    }
}

class InstrumentedPDOStatement {
    private $statement;
    private $query;

    public function __construct(\PDOStatement $statement, $query) {
        $this->statement = $statement;
        $this->query = $query;
    }

    public function execute($params = null) {
        $spanData = \Last9\createSpan(
            'database.query',
            \Last9\Instrumentation::getRootSpanId(),
            [
                ['key' => 'db.system', 'value' => ['stringValue' => 'mariadb']],
                ['key' => 'db.statement', 'value' => ['stringValue' => $this->query]],
                ['key' => 'db.type', 'value' => ['stringValue' => 'sql']],
                ['key' => 'db.operation', 'value' => ['stringValue' => 'execute']],
                ['key' => 'db.parameters', 'value' => ['stringValue' => json_encode($params)]]
            ]
        );

        try {
            $result = $this->statement->execute($params);
            \Last9\endSpan($spanData, ['code' => 1]);
            return $result;
        } catch (\PDOException $e) {
            \Last9\endSpan($spanData, 
                ['code' => 2, 'message' => $e->getMessage()],
                [
                    ['key' => 'error.message', 'value' => ['stringValue' => $e->getMessage()]],
                    ['key' => 'error.code', 'value' => ['stringValue' => $e->getCode()]],
                    ['key' => 'error.type', 'value' => ['stringValue' => get_class($e)]]
                ]
            );
            throw $e;
        }
    }

    public function __call($method, $args) {
        return call_user_func_array([$this->statement, $method], $args);
    }
}