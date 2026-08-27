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
