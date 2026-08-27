//! Behaviour. Each submodule owns one plugin so `main` stays a list of plugins
//! rather than a list of systems.

pub mod camera;
pub mod debug;
pub mod map;

// Only the fallback. The animated surface is `private::water`, chosen in
// `main` when the `water` feature is on.
#[cfg(not(feature = "water"))]
pub mod water;
