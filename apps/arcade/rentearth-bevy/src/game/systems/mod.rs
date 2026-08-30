//! Behaviour. Each submodule owns one plugin so `main` stays a list of plugins
//! rather than a list of systems.

pub mod borders;
pub mod camera;
pub mod city;
pub mod debug;
pub mod harvest;
pub mod map;
pub mod territory;
pub mod ui;

// Only the fallback. The animated surface is `private::water`, chosen in
// `main` when the `water` feature is on.
#[cfg(not(feature = "water"))]
pub mod water;
