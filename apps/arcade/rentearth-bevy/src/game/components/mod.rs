//! Data attached to entities. No behaviour -- systems read and write these.

pub mod camera;
pub mod tile;
// Only the encrypted renderer reads these, so without its feature they are
// ten dead-code warnings and nothing else.
#[cfg(feature = "units")]
pub mod unit;
