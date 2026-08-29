//! Compiles the generated Rust.
//!
//! Nothing depends on this crate; it exists so a schema that generates but
//! does not compile fails here rather than in a Bevy crate downstream.
#![allow(clippy::all)]

include!("../../../gen/rust/mod.rs");

/// The service code, which nothing else includes.
///
/// The tonic plugin runs with `no_include`, so the generated clients and
/// servers are referenced only by kbve-proto's `grpc` feature. That is a
/// feature, so an ordinary build never compiles them -- and generated code
/// nothing compiles is generated code nobody checks. This mirrors what
/// kbve-proto does, unconditionally, so a service that generates code no
/// toolchain will accept still fails here.
///
/// Kept in step by hand: a new service in the schemas needs a line here and a
/// line in kbve-proto. If the two ever disagree, this is the one that catches
/// it first.
pub mod grpc {
    macro_rules! service {
        ($name:ident, $pkg:ident, $file:literal) => {
            pub mod $name {
                mod generated {
                    pub use crate::kbve::$pkg::v1::*;
                    include!(concat!("../../../gen/rust/", $file));
                }
                pub use generated::*;
            }
        };
    }

    service!(redis, redis, "kbve/redis/v1/kbve.redis.v1.tonic.rs");
    service!(
        clickhouse,
        clickhouse,
        "kbve/clickhouse/v1/kbve.clickhouse.v1.tonic.rs"
    );
}
