// Compiles every generated Rust module.
//
// The crate has no source of its own; this file exists only to pull the
// generated module tree into a compilation unit. Without it cargo finds no
// target, reports "no targets specified in the manifest", and a broken schema
// sails through the check that was supposed to catch it.
#![allow(clippy::all)]
include!("../../../gen/rust/mod.rs");
