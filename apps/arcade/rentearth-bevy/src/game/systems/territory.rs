//! Who holds which hex.
//!
//! Kept apart from anything that changes it, because what owns ground and what
//! takes it are different questions and this has already outlived one answer:
//! it was written for a turn clock that no longer exists.

use bevy::prelude::*;

use crate::game::core::map::{MapSpec, Offset};

/// How many sides play.
pub const TEAMS: u32 = 4;

/// Which of them is a person. The other three are for something to be written
/// against later.
pub const HUMAN: u32 = 0;

/// Nobody's land.
const UNOWNED: u8 = u8::MAX;

/// Who owns each tile.
///
/// One byte a tile rather than a set per side: the question asked of this is
/// almost always "whose is this one", and answering that by searching four
/// sets is the wrong way round. Twenty-odd thousand bytes for the whole world.
#[derive(Resource)]
pub struct Territory {
    owner: Vec<u8>,
}

impl Territory {
    pub fn new(spec: MapSpec) -> Self {
        Self {
            owner: vec![UNOWNED; spec.tile_count() as usize],
        }
    }

    /// Whose tile this is. What selection and borders both ask.
    #[allow(dead_code)]
    pub fn owner_of(&self, spec: MapSpec, tile: Offset) -> Option<u32> {
        match self.owner.get(tile.wrapped(spec).index(spec)).copied() {
            Some(UNOWNED) | None => None,
            Some(team) => Some(team as u32),
        }
    }

    pub fn claim(&mut self, spec: MapSpec, tile: Offset, team: u32) {
        if let Some(slot) = self.owner.get_mut(tile.wrapped(spec).index(spec)) {
            *slot = team as u8;
        }
    }

    /// Every tile a side holds.
    ///
    /// Allocates, and is meant to: this is asked once when something needs to
    /// place a man or grow a border, not per frame and not per unit.
    pub fn held_by(&self, spec: MapSpec, team: u32) -> Vec<Offset> {
        self.owner
            .iter()
            .enumerate()
            .filter(|(_, owner)| **owner == team as u8)
            .map(|(index, _)| Offset {
                col: index as i32 % spec.cols,
                row: index as i32 / spec.cols,
            })
            .collect()
    }

    /// The held tiles with something not held beside them.
    ///
    /// The edge of what a side controls, which is the only part of it worth
    /// walking: an interior tile is guarded by the ring of tiles around it,
    /// and a patrol that visited every hex an empire owned would spend its
    /// life in the middle of one.
    pub fn frontier(&self, spec: MapSpec, team: u32) -> Vec<Offset> {
        self.held_by(spec, team)
            .into_iter()
            .filter(|tile| {
                tile.neighbours()
                    .iter()
                    .any(|raw| self.owner_of(spec, raw.wrapped(spec)) != Some(team))
            })
            .collect()
    }

    pub fn tiles_of(&self, team: u32) -> usize {
        self.owner.iter().filter(|o| **o == team as u8).count()
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    /// Unowned has to be a real answer, not team zero by accident -- which is
    /// exactly what it would be if the empty value were 0 rather than none.
    #[test]
    fn empty_land_belongs_to_nobody() {
        let spec = MapSpec::default();
        let mut territory = Territory::new(spec);
        let tile = Offset { col: 3, row: 3 };

        assert_eq!(territory.owner_of(spec, tile), None);
        assert_eq!(territory.tiles_of(HUMAN), 0);

        territory.claim(spec, tile, HUMAN);
        assert_eq!(territory.owner_of(spec, tile), Some(HUMAN));
        assert_eq!(territory.tiles_of(HUMAN), 1);
    }

    /// A claim off the edge of the map is a claim on the tile that wraps to,
    /// not a panic and not a write into somebody else's row.
    #[test]
    fn a_claim_wraps() {
        let spec = MapSpec::default();
        let mut territory = Territory::new(spec);

        territory.claim(spec, Offset { col: spec.cols, row: 2 }, 2);

        assert_eq!(territory.owner_of(spec, Offset { col: 0, row: 2 }), Some(2));
        assert_eq!(territory.tiles_of(2), 1);
    }

    /// A patrol should walk the edge, not the middle. A tile ringed entirely
    /// by its own side is not frontier however far from home it sits, and one
    /// on the coast is frontier even though the sea will never take it.
    #[test]
    fn the_frontier_is_the_edge_of_what_is_held() {
        let spec = MapSpec {
            cols: 12,
            rows: 12,
            ..MapSpec::default()
        };
        let mut territory = Territory::new(spec);

        let middle = Offset { col: 5, row: 5 };
        territory.claim(spec, middle, 0);
        for raw in middle.neighbours() {
            territory.claim(spec, raw.wrapped(spec), 0);
        }

        let frontier = territory.frontier(spec, 0);
        assert!(
            !frontier.contains(&middle),
            "a tile with only its own side around it is not the edge",
        );
        assert_eq!(frontier.len(), 6, "the ring is the edge, all of it");
    }
}
