//! Turns, and who owns what.
//!
//! The clock the whole game runs on. Everything that used to happen because a
//! frame went past now happens because a turn did, which is a smaller number
//! and a much better defined one: a unit moves when it is ordered and has
//! movement left, not because sixty milliseconds elapsed.

use bevy::prelude::*;

use crate::game::core::map::{MapSpec, Offset};

/// How many sides play.
pub const TEAMS: u32 = 4;

/// Which of them is a person.
///
/// The other three are for something to be written against later. Nothing here
/// knows the difference except whether a turn waits to be ended or ends
/// itself, which is deliberately the only difference: an AI that cannot be
/// swapped in for the player is an AI playing a different game.
pub const HUMAN: u32 = 0;

/// Whose turn it is, and which turn.
#[derive(Resource, Debug)]
pub struct Turn {
    pub number: u32,
    pub team: u32,
}

impl Default for Turn {
    fn default() -> Self {
        Self {
            number: 1,
            team: HUMAN,
        }
    }
}

impl Turn {
    pub fn is_human(&self) -> bool {
        self.team == HUMAN
    }

    /// Hand play to the next side, and count a turn when it comes back round.
    fn pass(&mut self) {
        self.team = (self.team + 1) % TEAMS;
        if self.team == HUMAN {
            self.number += 1;
        }
    }
}

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

    pub fn tiles_of(&self, team: u32) -> usize {
        self.owner.iter().filter(|o| **o == team as u8).count()
    }
}

/// End the player's turn on a key.
fn end_turn(keys: Res<ButtonInput<KeyCode>>, mut turn: ResMut<Turn>) {
    if turn.is_human() && keys.just_pressed(KeyCode::Enter) {
        turn.pass();
    }
}

/// The other three sides take their turn.
///
/// Which is, for now, to pass. They exist as turns before they exist as
/// players on purpose: the loop is what needs proving first, and a side that
/// does nothing still has to be dealt a turn, produce its unit and hand play
/// on. Something that plays goes here and nothing around it changes.
fn take_ai_turns(mut turn: ResMut<Turn>) {
    if !turn.is_human() {
        turn.pass();
    }
}

/// Say what happened, since a turn passing is otherwise invisible.
fn report(turn: Res<Turn>, territory: Option<Res<Territory>>) {
    if !turn.is_changed() || !turn.is_human() {
        return;
    }
    let Some(territory) = territory else {
        return;
    };
    info!(
        "turn {} -- your {} tiles",
        turn.number,
        territory.tiles_of(HUMAN),
    );
}

pub struct TurnPlugin;

impl Plugin for TurnPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<Turn>()
            .add_systems(Update, (end_turn, take_ai_turns, report).chain());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Four sides get a turn each before the number moves. Counting a turn per
    /// side would run the clock four times too fast, and every rate in the
    /// game is written against this number.
    #[test]
    fn a_turn_is_all_four_sides() {
        let mut turn = Turn::default();
        assert_eq!((turn.number, turn.team), (1, HUMAN));

        for expected in 1..TEAMS {
            turn.pass();
            assert_eq!(turn.team, expected);
            assert_eq!(turn.number, 1, "the turn moved before everyone played");
        }

        turn.pass();
        assert_eq!((turn.number, turn.team), (2, HUMAN));
    }

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
}
