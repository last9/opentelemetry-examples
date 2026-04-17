Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :users, only: [:index, :show, :create, :update, :destroy]

      # Payment namespace
      scope :payment do
        get 'status', to: 'payment#status'
        post 'process', to: 'payment#process_payment'
        post 'refund', to: 'payment#refund'
        get 'transactions', to: 'payment#transactions'
      end

      # Auth namespace
      scope :auth do
        post 'login', to: 'auth#login'
        post 'logout', to: 'auth#logout'
        post 'refresh', to: 'auth#refresh'
        get 'verify', to: 'auth#verify'
        post 'register', to: 'auth#register'
      end

      # Internal namespace
      scope :internal do
        get 'health', to: 'internal#health'
        get 'metrics', to: 'internal#metrics'
        post 'sync', to: 'internal#sync'
        post 'cache/invalidate', to: 'internal#cache_invalidate'
        get 'config', to: 'internal#get_config'
        post 'jobs/trigger', to: 'internal#trigger_job'
      end

      # ClickHouse demo endpoints
      scope :clickhouse do
        # Direct — code.namespace reflects controller
        get  'tables',    to: 'clickhouse#tables_list'
        get  'columns',   to: 'clickhouse#columns_list'
        get  'databases', to: 'clickhouse#databases_list'
        get  'multi',     to: 'clickhouse#multi_query'
        get  'one',       to: 'clickhouse#select_one_row'
        get  'execute',   to: 'clickhouse#execute_query'
        post 'insert',         to: 'clickhouse#insert_row'
        post 'insert_rows',    to: 'clickhouse#insert_rows_direct'
        post 'insert_compact', to: 'clickhouse#insert_compact_direct'

        # Via service — code.namespace reflects ClickhouseSystemService
        scope :svc do
          get  'tables',    to: 'clickhouse#svc_tables'
          get  'columns',   to: 'clickhouse#svc_columns'
          get  'databases', to: 'clickhouse#svc_databases'
          get  'summary',   to: 'clickhouse#svc_summary'
          get  'one',            to: 'clickhouse#svc_one'
          post 'insert',         to: 'clickhouse#svc_insert'
          post 'insert_rows',    to: 'clickhouse#svc_insert_rows'
          post 'insert_compact', to: 'clickhouse#svc_insert_compact'
        end
      end

      # Demo endpoints
      get 'demo/complex_queries',  to: 'demo#complex_queries'
      get 'demo/otel_v8_features', to: 'demo#otel_v8_features'
      get 'demo/redis',            to: 'demo#redis_demo'

      # Public endpoints - NO service.namespace attribute
      scope :public do
        get 'ping', to: 'public#ping'
        get 'version', to: 'public#version'
        get 'echo', to: 'public#echo'
        post 'echo', to: 'public#echo_post'
      end
    end
  end

  # Shallow health check — excluded from body capture by DEFAULT_EXCLUDE_PATHS
  get "/health", to: proc { [200, { "Content-Type" => "application/json" }, ['{"status":"ok"}']] }

  resource :checkout, only: [:new, :create], controller: 'checkout' do
    get 'payment', on: :collection
    post 'confirm', on: :collection
    get 'complete', on: :collection
  end
end
