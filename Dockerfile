# ============================================================
# Stage 1: Build — Alpine + musl (binario estático)
# ============================================================
FROM rust:1-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /app

# Copiar solo lo necesario para compilar
COPY Cargo.toml ./
COPY core/ core/
COPY server/ server/

# Compilar en release (estático con musl)
RUN cargo build --release -p azuldesk-server && \
    strip target/release/azuldesk-server

# ============================================================
# Stage 2: Runtime — scratch (0 bytes, solo el binario)
# ============================================================
FROM scratch
COPY --from=builder /app/target/release/azuldesk-server /azuldesk-server
EXPOSE 7980 7981
ENTRYPOINT ["/azuldesk-server"]
