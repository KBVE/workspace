//! Struct-level text cleaning.
//!
//! The point of this crate is that a cleaning rule lives next to the field it
//! applies to, rather than at each call site that happens to remember it:
//!
//! ```ignore
//! #[derive(Sanitize)]
//! struct Registration {
//!     #[holy(sanitize = "trim,lowercase")]
//!     username: String,
//! }
//! ```
//!
//! This is the facade. The derives come from `holy-derive`, and the code they
//! generate calls back into this crate. A proc-macro crate can export macros
//! and nothing else, which is why the two are separate -- the same split
//! `serde` and `thiserror` use.
pub use holy_derive::{Fuzz, Getters, Observer, Sanitize, Setters};
