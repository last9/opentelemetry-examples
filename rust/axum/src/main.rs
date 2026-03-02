use async_graphql::{extensions::Tracing, Context, EmptyMutation, EmptySubscription, Object, Schema};
use async_graphql_axum::{GraphQLRequest, GraphQLResponse};
use axum::{
    extract::{Path, State},
    middleware,
    response::{Html, Json},
    routing::{get, post},
    Router,
};
use rusqlite::{params, Connection};
use otel_rust_axum::{client::TracedClient, current_trace_id, db as otel_db, init};
use otel_rust_axum::layer::{OtelLayer, record_matched_route};
use serde::Serialize;
use std::{
    net::SocketAddr,
    sync::{Arc, Mutex},
};
use tracing::info;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

#[derive(Serialize, Clone)]
struct User {
    id: u32,
    name: String,
    email: String,
}

// async-graphql requires Object to be implemented on a type; derive Clone so
// it can be returned from resolvers.
#[async_graphql::Object]
impl User {
    async fn id(&self) -> u32 { self.id }
    async fn name(&self) -> &str { &self.name }
    async fn email(&self) -> &str { &self.email }
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
    service: &'static str,
}

type Db = Arc<Mutex<Connection>>;

// ---------------------------------------------------------------------------
// GraphQL schema
// ---------------------------------------------------------------------------

struct QueryRoot;

#[Object]
impl QueryRoot {
    /// List all users.
    async fn users(&self, ctx: &Context<'_>) -> Vec<User> {
        let db = ctx.data_unchecked::<Db>().clone();
        fetch_users_from_db(db).await
    }

    /// Look up a single user by ID.
    async fn user(&self, ctx: &Context<'_>, id: u32) -> Option<User> {
        let db = ctx.data_unchecked::<Db>().clone();
        find_user(db, id).await
    }
}

type AppSchema = Schema<QueryRoot, EmptyMutation, EmptySubscription>;

// ---------------------------------------------------------------------------
// App state — holds both DB and schema so both are accessible from handlers
// ---------------------------------------------------------------------------

#[derive(Clone)]
struct AppState {
    db: Db,
    schema: AppSchema,
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() {
    let _guard = init().expect("Failed to initialize OpenTelemetry");

    let conn = Connection::open_in_memory().expect("Failed to open SQLite");
    seed_db(&conn).expect("Failed to seed database");
    let db: Db = Arc::new(Mutex::new(conn));

    // Build the GraphQL schema.
    // .extension(Tracing) makes async-graphql emit tracing spans for each
    // GraphQL phase (parse, validate, execute, field resolution). These flow
    // into the OTel pipeline automatically via tracing-opentelemetry — no
    // extra wiring needed. Do NOT use the "opentelemetry" feature flag on
    // async-graphql; it pins otel 0.21 which conflicts with our otel 0.27.
    let schema = Schema::build(QueryRoot, EmptyMutation, EmptySubscription)
        .extension(Tracing)
        .data(db.clone())
        .finish();

    let state = AppState { db, schema };

    let app = Router::new()
        .route("/", get(root))
        .route("/health", get(health))
        .route("/users", get(list_users))
        .route("/users/:id", get(get_user))
        .route("/external", get(external_call))
        .route("/graphql", post(graphql_handler))
        .route("/graphiql", get(graphiql))
        // route_layer runs AFTER routing — MatchedPath is available here
        .route_layer(middleware::from_fn(record_matched_route))
        .layer(OtelLayer::new())
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    info!("Listening on {}", addr);

    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

// ---------------------------------------------------------------------------
// DB setup
// ---------------------------------------------------------------------------

fn seed_db(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL);
         INSERT INTO users VALUES (1, 'Alice', 'alice@example.com');
         INSERT INTO users VALUES (2, 'Bob',   'bob@example.com');",
    )
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async fn root() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "message": "Hello from Rust + Axum + OTel 0.27" }))
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        service: "rust-axum-service",
    })
}

async fn list_users(State(state): State<AppState>) -> Json<Vec<User>> {
    info!(trace_id = %current_trace_id(), "Fetching all users");
    let users = fetch_users_from_db(state.db).await;
    info!(trace_id = %current_trace_id(), count = users.len(), "Returning users");
    Json(users)
}

async fn get_user(
    State(state): State<AppState>,
    Path(id): Path<u32>,
) -> Result<Json<User>, axum::http::StatusCode> {
    info!(trace_id = %current_trace_id(), user_id = id, "Looking up user");
    match find_user(state.db, id).await {
        Some(user) => Ok(Json(user)),
        None => Err(axum::http::StatusCode::NOT_FOUND),
    }
}

async fn external_call() -> Result<Json<serde_json::Value>, axum::http::StatusCode> {
    info!(trace_id = %current_trace_id(), "Starting external HTTP call");
    fetch_external_data().await.map(Json).map_err(|e| {
        tracing::error!(
            trace_id = %current_trace_id(),
            error = %e,
            "External API call failed"
        );
        axum::http::StatusCode::BAD_GATEWAY
    })
}

/// GraphQL endpoint. OtelLayer creates the HTTP server span; async-graphql's
/// Tracing extension adds child spans for parse / validate / execute / field.
async fn graphql_handler(
    State(state): State<AppState>,
    req: GraphQLRequest,
) -> GraphQLResponse {
    state.schema.execute(req.into_inner()).await.into()
}

/// GraphiQL playground — open http://localhost:8080/graphiql in a browser.
async fn graphiql() -> Html<String> {
    Html(async_graphql::http::GraphiQLSource::build().endpoint("/graphql").finish())
}

// ---------------------------------------------------------------------------
// Business logic
// ---------------------------------------------------------------------------

async fn fetch_users_from_db(db: Db) -> Vec<User> {
    const SQL: &str = "SELECT id, name, email FROM users ORDER BY id";
    // Create the span and move it into spawn_blocking — enter() inside the
    // sync closure so no !Send guard crosses the .await boundary.
    let span = otel_db::sqlite_span("SELECT", SQL, "users");

    tokio::task::spawn_blocking(move || {
        let _enter = span.enter();
        let conn = db.lock().unwrap();
        let mut stmt = conn.prepare(SQL).unwrap();
        stmt.query_map([], |row| {
            Ok(User {
                id: row.get::<_, u32>(0)?,
                name: row.get(1)?,
                email: row.get(2)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
    })
    .await
    .unwrap_or_default()
}

async fn find_user(db: Db, id: u32) -> Option<User> {
    const SQL: &str = "SELECT id, name, email FROM users WHERE id = ?1";
    let span = otel_db::sqlite_span("SELECT", SQL, "users");

    tokio::task::spawn_blocking(move || {
        let _enter = span.enter();
        let conn = db.lock().unwrap();
        conn.query_row(SQL, params![id], |row| {
            Ok(User {
                id: row.get::<_, u32>(0)?,
                name: row.get(1)?,
                email: row.get(2)?,
            })
        })
        .ok()
    })
    .await
    .unwrap_or(None)
}

async fn fetch_external_data() -> Result<serde_json::Value, reqwest::Error> {
    TracedClient::new()
        .get("https://httpbin.org/json")
        .send()
        .await?
        .json::<serde_json::Value>()
        .await
}
