//! api.rentearth.com
//!
//! The site is static and fetches from here at runtime, so every response
//! shape is a type out of `packages/protobuf`. JSON is the wire format: the
//! browser is the client, and the schemas are the contract rather than the
//! encoding.

mod locale;

use axum::{Json, Router, http::HeaderValue, http::Method, routing::get};
use serde::Serialize;
use std::net::SocketAddr;
use tower_http::{compression::CompressionLayer, cors::CorsLayer, trace::TraceLayer};

#[derive(Debug, Serialize)]
struct Health {
    status: &'static str,
    version: &'static str,
}

async fn health() -> Json<Health> {
    Json(Health {
        status: "ok",
        version: env!("CARGO_PKG_VERSION"),
    })
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Locales {
    locales: Vec<locale::LocaleView>,
    default_tag: String,
}

async fn locales() -> Json<Locales> {
    let locales = locale::all();
    let default_tag = locales
        .iter()
        .find(|view| view.proto == locale::DEFAULT.as_str_name())
        .map(|view| view.tag.clone())
        .unwrap_or_default();
    Json(Locales {
        locales,
        default_tag,
    })
}

fn app(origin: HeaderValue) -> Router {
    Router::new()
        .route("/healthz", get(health))
        .route("/v1/locales", get(locales))
        // The site is served from another origin, so without this the browser
        // drops every response before the page sees it.
        .layer(
            CorsLayer::new()
                .allow_origin(origin)
                .allow_methods([Method::GET]),
        )
        .layer(CompressionLayer::new())
        .layer(TraceLayer::new_for_http())
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,tower_http=debug".into()),
        )
        .init();

    let origin =
        std::env::var("ALLOWED_ORIGIN").unwrap_or_else(|_| "https://rentearth.com".to_string());
    let origin: HeaderValue = origin
        .parse()
        .expect("ALLOWED_ORIGIN is not a valid header value");

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(8080);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|error| panic!("cannot bind {addr}: {error}"));
    tracing::info!("listening on {addr}");

    axum::serve(listener, app(origin))
        .await
        .expect("server failed");
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn locales_endpoint_returns_the_schema_locales() {
        let response = app(HeaderValue::from_static("*"))
            .oneshot(
                Request::builder()
                    .uri("/v1/locales")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(value["defaultTag"], "en");
        assert_eq!(value["locales"][0]["proto"], "LOCALE_EN");
    }
}
