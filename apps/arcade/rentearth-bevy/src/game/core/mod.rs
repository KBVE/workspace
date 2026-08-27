//! Pure map logic: coordinates, world shape, terrain generation.
//!
//! Nothing here touches the ECS beyond deriving `Component` on the coordinate
//! type. It is the layer that has to stay testable and engine-agnostic, so the
//! rule is one-directional: `systems` may call `core`, never the reverse.

pub mod depth;
pub mod earth;
pub mod hex;
pub mod map;
pub mod terrain;
