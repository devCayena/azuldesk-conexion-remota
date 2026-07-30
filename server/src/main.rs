mod api;
mod db;
mod ca;
mod signaling;
mod audio_relay;

use anyhow::Result;
use clap::{Parser, Subcommand};
use db::Database;
use ca::CertificateAuthority;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::broadcast;
use tracing_subscriber::{EnvFilter, Registry, fmt, filter::LevelFilter};
use tracing_subscriber::layer::{Layer, SubscriberExt};
use tracing_subscriber::util::SubscriberInitExt;
use tracing_appender::non_blocking;
use std::fs::OpenOptions;

#[derive(Parser)]
#[command(name = "azuldesk-server", version, about = "AzulDesk remote desktop server")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    #[arg(long, env = "DATABASE_URL", default_value = "postgres://spyware:password@localhost:5432/spyware", global = true)]
    database_url: String,
}

#[derive(Subcommand)]
enum Commands {
    /// Crear un usuario (admin o support)
    CreateAdmin {
        #[arg(long)]
        id: String,
        #[arg(long)]
        name: String,
        #[arg(long)]
        email: String,
        #[arg(long)]
        password: String,
        #[arg(long, default_value = "admin")]
        role: String,
    },
    /// Iniciar el servidor
    #[command(hide = true)]
    Serve {
        #[arg(long, env = "SERVER_HOST", default_value = "0.0.0.0")]
        host: String,
        #[arg(long, env = "SERVER_PORT", default_value_t = 7980)]
        port: u16,
        #[arg(long, env = "RELAY_ENABLED", default_value_t = false)]
        relay_enabled: bool,
        #[arg(long, env = "RELAY_HOST", default_value = "0.0.0.0")]
        relay_host: String,
        #[arg(long, env = "RELAY_PORT", default_value_t = 7981)]
        relay_port: u16,
    },
}

pub struct AppState {
    pub peers: tokio::sync::RwLock<std::collections::HashMap<azuldesk_core::types::PeerId, azuldesk_core::protocol::OnlinePeer>>,
    pub broadcast: broadcast::Sender<String>,
    pub db: Database,
    pub ca: CertificateAuthority,
    pub relay_enabled: bool,
    pub relay_host: String,
    pub relay_port: u16,
    pub updates_dir: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let _ = dotenvy::dotenv();
    let cli = Cli::parse();

    match cli.command {
        Some(Commands::CreateAdmin { id, name, email, password, role }) => {
            let hash = bcrypt::hash(&password, 12)?;
            let db = Database::open(&cli.database_url).await?;
            let is_admin = role == "admin";
            let user_id = db.create_user(&id, &name, &email, &hash, is_admin, &role).await?;
            println!("User created: id={}, email={}, role={}, user_id={}", id, email, role, user_id);
            return Ok(());
        }
        Some(Commands::Serve { host, port, relay_enabled, relay_host, relay_port }) => {
            let updates_dir = std::env::var("UPDATES_DIR").unwrap_or_else(|_| "./updates".to_string());
            run_server(cli.database_url, host, port, relay_enabled, relay_host, relay_port, updates_dir).await?;
        }
        None => {
            let host = std::env::var("SERVER_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
            let port: u16 = std::env::var("SERVER_PORT").ok().and_then(|v| v.parse().ok()).unwrap_or(7980);
            let relay_enabled = std::env::var("RELAY_ENABLED").map(|v| v == "true").unwrap_or(false);
            let relay_host = std::env::var("RELAY_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
            let relay_port: u16 = std::env::var("RELAY_PORT").ok().and_then(|v| v.parse().ok()).unwrap_or(7981);
            let updates_dir = std::env::var("UPDATES_DIR").unwrap_or_else(|_| "./updates".to_string());
            run_server(cli.database_url, host, port, relay_enabled, relay_host, relay_port, updates_dir).await?;
        }
    }

    Ok(())
}

async fn run_server(database_url: String, host: String, port: u16, relay_enabled: bool, relay_host: String, relay_port: u16, updates_dir: String) -> Result<()> {
    // ─── Logging: access.log + error.log + stdout ───────
    let log_dir = std::env::var("LOG_DIR").unwrap_or_else(|_| "./logs".to_string());
    std::fs::create_dir_all(&log_dir)?;

    let access_file = OpenOptions::new()
        .create(true).append(true).open(format!("{}/access.log", log_dir))?;
    let error_file = OpenOptions::new()
        .create(true).append(true).open(format!("{}/error.log", log_dir))?;

    let (access_writer, _access_guard) = non_blocking(access_file);
    let (error_writer, _error_guard) = non_blocking(error_file);

    let subscriber = Registry::default()
        .with(fmt::layer()
            .with_writer(access_writer)
            .with_filter(LevelFilter::INFO))
        .with(fmt::layer()
            .with_writer(error_writer)
            .with_filter(LevelFilter::ERROR))
        .with(fmt::layer()
            .with_writer(std::io::stdout)
            .with_filter(EnvFilter::from_default_env()
                .add_directive("azuldesk_server=info".parse()?)));
    subscriber.init();

    let addr = format!("{}:{}", host, port);
    let listener = TcpListener::bind(&addr).await?;

    let db = Database::open(&database_url).await?;
    let ca = {
        let existing = db.get_ca().await?;
        let ca = CertificateAuthority::new_or_load(existing)?;
        db.store_ca(ca.ca_cert_pem(), ca.ca_key_pem()).await?;
        ca
    };

    if relay_enabled {
        tracing::info!("Relay enabled on {}:{}", relay_host, relay_port);
    }

    let (broadcast_tx, _) = broadcast::channel::<String>(256);
    // Ensure updates directory exists
    let _ = tokio::fs::create_dir_all(&updates_dir).await;

    let state = Arc::new(AppState {
        peers: tokio::sync::RwLock::new(std::collections::HashMap::new()),
        broadcast: broadcast_tx,
        db,
        ca,
        relay_enabled,
        relay_host,
        relay_port,
        updates_dir: updates_dir.clone(),
    });

    // Auto-generate master key every hour
    {
        let state = state.clone();
        tokio::spawn(async move {
            loop {
                let now = chrono::Utc::now();
                let valid_until = now + chrono::Duration::hours(1);
                let plain = {
                    use sha2::Digest;
                    let mut h = sha2::Sha256::new();
                    h.update(uuid::Uuid::new_v4().to_string());
                    h.update(now.to_rfc3339());
                    hex::encode(h.finalize())[..32].to_uppercase()
                };
                let hash = {
                    use sha2::Digest;
                    let mut h = sha2::Sha256::new();
                    h.update(plain.as_bytes());
                    hex::encode(h.finalize())
                };
                if let Err(e) = state.db.create_master_key_direct(&plain, &hash, &now, &valid_until, None, "auto").await {
                    tracing::error!("Failed to auto-generate master key: {}", e);
                } else {
                    tracing::info!("Auto-generated master key valid until {}", valid_until.to_rfc3339());
                }
                tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
            }
        });
    }

    tracing::info!("Signaling server on ws://{}", addr);

    let app = api::router(state.clone())
        .layer(tower_http::trace::TraceLayer::new_for_http())
        .nest_service("/updates", tower_http::services::ServeDir::new(updates_dir.clone()));
    let http_addr = format!("{}:{}", host, port + 1);
    tokio::spawn(async move {
        let listener = tokio::net::TcpListener::bind(&http_addr).await.unwrap();
        tracing::info!("REST API on http://{}", http_addr);
        axum::serve(listener, app).await.unwrap();
    });

    loop {
        let (stream, peer_addr) = listener.accept().await?;
        let state = state.clone();
        tokio::spawn(async move {
            if let Err(e) = signaling::handle_connection(stream, peer_addr, state).await {
                tracing::debug!("Connection closed: {}", e);
            }
        });
    }
}
