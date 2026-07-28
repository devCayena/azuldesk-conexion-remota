use anyhow::Result;
use clap::Parser;

#[derive(Parser)]
#[command(name = "azuldesk-relay", version, about = "AzulDesk relay server for P2P fallback")]
struct Args {
    #[arg(long, default_value = "0.0.0.0")]
    host: String,

    #[arg(long, default_value_t = 7981)]
    port: u16,

    #[arg(long, default_value_t = 5000)]
    max_bandwidth_mbps: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("azuldesk_relay=info")
        .init();

    let args = Args::parse();
    tracing::info!("AzulDesk relay server starting on {}:{}", args.host, args.port);

    Ok(())
}
