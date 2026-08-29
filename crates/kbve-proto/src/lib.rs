//! The generated prost output lives in `packages/protobuf/gen/rust`, which is
//! gitignored and written by `moon run protobuf:build`. Including it from
//! there rather than copying it in keeps a single generated tree for every
//! consumer; `include!` resolves the nested paths relative to `mod.rs`, so the
//! whole module tree comes along.
#![allow(clippy::all)]

include!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../packages/protobuf/gen/rust/mod.rs"
));

pub use kbve::*;

/// A ULID's textual form, or `None` when there is not one to render.
///
/// The schema carries a ULID as its sixteen bytes rather than its twenty-six
/// characters, and says the textual encoding belongs at the edges. A registry
/// looked up by a string out of a content file is such an edge, and five of
/// them wanted the same four lines, so the conversion lives beside the type it
/// converts.
///
/// Anything that is not exactly sixteen bytes is not a ULID. It is dropped
/// rather than rendered into something no caller would ever search for.
pub fn ulid_text(id: Option<&kbve::r#type::v1::Ulid>) -> Option<String> {
    let bytes: [u8; 16] = id?.value.as_slice().try_into().ok()?;
    Some(ulid::Ulid::from_bytes(bytes).to_string())
}

/// The gRPC clients and servers, behind the `grpc` feature.
///
/// The tonic plugin writes these to a file per package and, with `no_include`,
/// leaves them unreferenced -- which is the point: an include! inside the
/// message file could not be switched off. The generated code names its
/// messages `super::RedisCommand`, and puts its client and server in nested
/// modules of their own, so `super` is the module holding the include -- which
/// is where the re-export of the package has to go.
///
/// Only the two schemas that declare a service appear here. Adding a service
/// to a schema means adding four lines below; nothing finds it automatically,
/// which is worth knowing before wondering where a new client went.
#[cfg(feature = "grpc")]
pub mod grpc {
    macro_rules! service {
        ($name:ident, $pkg:ident, $file:literal) => {
            pub mod $name {
                mod generated {
                    // Inside the include, `super` is this module rather than
                    // the one below: the generated code puts its client and
                    // server in modules of their own, so the re-export has to
                    // sit beside the include and not one level out.
                    pub use crate::kbve::$pkg::v1::*;
                    include!(concat!(
                        env!("CARGO_MANIFEST_DIR"),
                        "/../../packages/protobuf/gen/rust/",
                        $file
                    ));
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
