//! Taking ground off a side that already holds it.
//!
//! Nothing calls this yet, and that is on purpose. Settling -- claiming empty
//! land on a clock -- is a rule with one input and no argument to lose; taking
//! a held tile is a fight, and a fight needs whatever supplies force to exist
//! first. This is the half that does not depend on that: the bookkeeping of a
//! siege, written and tested against nothing but the map and the owner table,
//! so that when men or citizens or a war score turn up they only have to say
//! *how hard* and not *what happens next*.
//!
//! The seam is [`Push`]: a tile, a side, and a number. Whoever fills that
//! number in later -- soldiers standing on the tile, a city's populace, an
//! artillery train -- is free to, and none of it reaches in here.
//!
//! Deliberately kept off `Territory` itself. Who owns a tile and who is trying
//! to change that are different questions, and [`territory`](super::territory)
//! has already outlived one answer to the second.

#![allow(dead_code)]

use std::collections::HashMap;

use bevy::prelude::*;

use crate::game::core::map::{MapSpec, Offset};

use super::territory::Territory;

/// Pressure needed to flip an undefended tile.
///
/// A number rather than a duration: strength is per second, so a lone push of
/// strength 10 takes ten seconds and ten of them take one. That the same total
/// effort wins either way is the point -- it makes a slow siege and a sudden
/// storm cost the same, and lets the thing that supplies strength decide which
/// one a player is looking at.
pub const HOLD: f32 = 100.0;

/// How much each held neighbour stiffens a tile.
///
/// A tile deep inside a realm has all six and costs 2.5x an exposed one; a
/// tile jutting out on a peninsula costs barely more than empty ground. This
/// is the mirror of how borders grow -- settling fills the snuggest tile
/// first, so conquest should peel the loosest one first, or a border would be
/// as easy to break in the middle as at the edge.
const SUPPORT: f32 = 0.25;

/// How fast an unpressed siege fades, as a fraction of [`HOLD`] per second.
///
/// Slower than it builds. Walking away should not undo an hour, but leaving a
/// tile half-taken forever is a way to bank sieges across a whole border and
/// cash them in at once, which is not a war -- it is a save file.
const EASE: f32 = 0.1;

/// One side leaning on one tile for one tick.
///
/// The whole of the interface. `strength` is per second, and what produces it
/// is not this module's business.
#[derive(Clone, Copy, Debug)]
pub struct Push {
    pub tile: Offset,
    pub team: u32,
    pub strength: f32,
}

/// A tile changing hands.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Fall {
    pub tile: Offset,
    pub from: u32,
    pub to: u32,
}

/// How far along each contested tile is.
///
/// A map rather than a byte per tile, unlike [`Territory`]: ownership is asked
/// about every tile and answered constantly, whereas a siege is a handful of
/// tiles on a frontier. Paying for twenty thousand floats to track six of them
/// is the wrong way round.
#[derive(Resource, Default)]
pub struct Siege {
    /// Attacker and progress, by tile. One attacker a tile -- see
    /// [`Siege::advance`] for what happens when a second one turns up.
    fronts: HashMap<Offset, (u32, f32)>,
}

impl Siege {
    /// How far along a tile is, from `0.0` to `1.0`, and who is pressing it.
    ///
    /// What a border or a healthbar would draw.
    pub fn front(&self, spec: MapSpec, territory: &Territory, tile: Offset) -> Option<(u32, f32)> {
        let (team, pressure) = self.fronts.get(&tile.wrapped(spec)).copied()?;
        Some((team, (pressure / cost(spec, territory, tile)).clamp(0.0, 1.0)))
    }

    /// Advance every siege by one tick and report what fell.
    ///
    /// Pushes on tiles that cannot legally be pressed are dropped rather than
    /// rejected: the thing supplying strength is a unit system deciding where
    /// men are standing, and men stand on plenty of tiles that are nobody's to
    /// take. Making that an error would push this module's rules out into
    /// theirs.
    ///
    /// Tiles nobody pushed this tick ease off, and a tile that eases to
    /// nothing is forgotten, so the map stays the size of the fighting.
    pub fn advance(
        &mut self,
        spec: MapSpec,
        territory: &Territory,
        pushes: &[Push],
        delta: f32,
    ) -> Vec<Fall> {
        // Strength on the same tile by the same side adds up: two companies
        // besieging one place are one siege, not two that overwrite each other.
        let mut leaning: HashMap<(Offset, u32), f32> = HashMap::new();
        for push in pushes {
            let tile = push.tile.wrapped(spec);
            if !may_press(spec, territory, tile, push.team) || push.strength <= 0.0 {
                continue;
            }
            *leaning.entry((tile, push.team)).or_default() += push.strength;
        }

        // The strongest side on each tile is the one besieging it. A tile two
        // rivals are both leaning on is not shared between them -- whoever
        // brought less is fighting the wrong enemy, and their effort is not
        // banked for later.
        let mut best: HashMap<Offset, (u32, f32)> = HashMap::new();
        for ((tile, team), strength) in leaning {
            // Ties go to the lower-numbered side rather than to whichever the
            // map happened to yield first, so a replay is a replay.
            let wins = match best.get(&tile) {
                None => true,
                Some((held, seen)) => strength > *seen || (strength == *seen && team < *held),
            };
            if wins {
                best.insert(tile, (team, strength));
            }
        }

        let mut fallen = Vec::new();

        for (tile, (team, strength)) in &best {
            let entry = self.fronts.entry(*tile).or_insert((*team, 0.0));
            // A siege taken over by somebody else starts again. The previous
            // attacker's work was against a garrison they are no longer facing.
            if entry.0 != *team {
                *entry = (*team, 0.0);
            }
            entry.1 += strength * delta;

            if entry.1 >= cost(spec, territory, *tile) {
                if let Some(from) = territory.owner_of(spec, *tile) {
                    fallen.push(Fall {
                        tile: *tile,
                        from,
                        to: *team,
                    });
                }
            }
        }

        // A fallen tile's siege is over -- the caller claims it, and next tick
        // it is the new owner's ground and no longer pressable by them at all.
        for fall in &fallen {
            self.fronts.remove(&fall.tile);
        }

        let ease = HOLD * EASE * delta;
        self.fronts.retain(|tile, (_, pressure)| {
            if best.contains_key(tile) {
                return true;
            }
            *pressure -= ease;
            *pressure > 0.0
        });

        // Ordered, because the caller may be applying these to a world other
        // people are watching and a HashMap's order is not a decision anybody
        // made.
        fallen.sort_unstable_by_key(|fall| (fall.tile.row, fall.tile.col));
        fallen
    }

    /// Forget a tile's siege. For when the ground changes hands some other way
    /// -- a treaty, a city falling, a side leaving the game.
    pub fn lift(&mut self, spec: MapSpec, tile: Offset) {
        self.fronts.remove(&tile.wrapped(spec));
    }
}

/// What a tile costs to take: [`HOLD`], stiffened by how much of its own ring
/// its owner also holds.
fn cost(spec: MapSpec, territory: &Territory, tile: Offset) -> f32 {
    let tile = tile.wrapped(spec);
    let Some(owner) = territory.owner_of(spec, tile) else {
        return HOLD;
    };

    let support = tile
        .neighbours()
        .iter()
        .filter(|ring| territory.owner_of(spec, ring.wrapped(spec)) == Some(owner))
        .count() as f32;

    HOLD * (1.0 + SUPPORT * support)
}

/// Whether a side may press a tile at all.
///
/// Somebody else's ground, and touching their own -- an army cannot besiege a
/// tile in the middle of an empire it has not reached. Empty land is not
/// conquest and is left to settling, which is slower but free.
fn may_press(spec: MapSpec, territory: &Territory, tile: Offset, team: u32) -> bool {
    let tile = tile.wrapped(spec);
    match territory.owner_of(spec, tile) {
        None => false,
        Some(owner) if owner == team => false,
        Some(_) => tile
            .neighbours()
            .iter()
            .any(|ring| territory.owner_of(spec, ring.wrapped(spec)) == Some(team)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn world() -> MapSpec {
        MapSpec {
            cols: 40,
            rows: 40,
            ..MapSpec::default()
        }
    }

    /// A border: the west half held by side 0, the east by side 1, meeting at
    /// column 20.
    fn split(spec: MapSpec) -> Territory {
        let mut territory = Territory::new(spec);
        for tile in spec.tiles() {
            territory.claim(spec, tile, u32::from(tile.col >= 20));
        }
        territory
    }

    /// Conquest is for held ground reachable from your own. Empty land belongs
    /// to settling and a tile deep in a rival's realm belongs to whoever gets
    /// there -- neither is a siege, and letting either through would make an
    /// army's reach the whole map.
    #[test]
    fn only_a_neighbours_ground_may_be_pressed() {
        let spec = world();
        let territory = split(spec);

        let border = Offset { col: 20, row: 10 };
        assert!(may_press(spec, &territory, border, 0));

        // Their side of the line, but not touching mine.
        assert!(!may_press(spec, &territory, Offset { col: 25, row: 10 }, 0));
        // My own.
        assert!(!may_press(spec, &territory, Offset { col: 19, row: 10 }, 0));
        // Nobody's.
        assert!(!may_press(spec, &Territory::new(spec), border, 0));
    }

    /// The same total effort wins whether it arrives slowly or all at once,
    /// and a tile with its whole ring behind it costs more than an exposed
    /// one. Without the second half a border is as thin in its middle as at
    /// its ends, and there is no reason to attack anywhere in particular.
    #[test]
    fn a_tile_falls_to_enough_pressure_and_a_backed_one_takes_more() {
        let spec = world();
        let territory = split(spec);
        let tile = Offset { col: 20, row: 10 };

        // Three of this tile's six neighbours are its owner's, so it stands at
        // 1.75x an exposed tile.
        let toll = cost(spec, &territory, tile);
        assert!(toll > HOLD, "a backed tile is dearer than open ground");

        let push = |strength| Push { tile, team: 0, strength };

        let mut slow = Siege::default();
        let mut fell = Vec::new();
        for _ in 0..20 {
            fell = slow.advance(spec, &territory, &[push(toll / 20.0)], 1.0);
        }
        assert_eq!(
            fell,
            vec![Fall { tile, from: 1, to: 0 }],
            "twenty ticks of a twentieth each should just carry it"
        );

        let mut sudden = Siege::default();
        let fell = sudden.advance(spec, &territory, &[push(toll)], 1.0);
        assert_eq!(fell, vec![Fall { tile, from: 1, to: 0 }], "or one tick of all of it");

        // And not a tick sooner.
        let mut short = Siege::default();
        assert!(
            short.advance(spec, &territory, &[push(toll * 0.9)], 1.0).is_empty(),
            "nine tenths is not a conquest"
        );
    }

    /// Walk away and the siege fades. Otherwise a side could lean on every
    /// tile of a border for a minute each, then take the lot in an afternoon
    /// with nothing standing there.
    #[test]
    fn an_abandoned_siege_fades_to_nothing() {
        let spec = world();
        let territory = split(spec);
        let tile = Offset { col: 20, row: 10 };

        let mut siege = Siege::default();
        siege.advance(
            spec,
            &territory,
            &[Push { tile, team: 0, strength: HOLD * 0.5 }],
            1.0,
        );
        let (team, part) = siege.front(spec, &territory, tile).expect("a siege is under way");
        assert_eq!(team, 0);
        assert!(part > 0.0 && part < 1.0);

        // Long enough to shed half of HOLD at EASE per second, and then some.
        for _ in 0..10 {
            assert!(siege.advance(spec, &territory, &[], 1.0).is_empty());
        }
        assert_eq!(siege.front(spec, &territory, tile), None, "the siege is forgotten");
    }

    /// Two rivals on one tile is one siege, and the weaker one's effort is not
    /// banked. A tile that remembered both would fall to whichever happened to
    /// stop pushing last.
    #[test]
    fn the_stronger_side_owns_the_siege() {
        let spec = world();
        let mut territory = split(spec);
        // A third side wedged against the same tile, so both 0 and 2 may press
        // it. One of its neighbours changes hands, not all of them -- side 0
        // has to keep a foot on the tile or it is not in this fight at all.
        let tile = Offset { col: 20, row: 10 };
        let mine = tile
            .neighbours()
            .into_iter()
            .map(|ring| ring.wrapped(spec))
            .filter(|ring| territory.owner_of(spec, *ring) == Some(0))
            .collect::<Vec<_>>();
        assert!(mine.len() > 1, "side 0 needs a tile to spare");
        territory.claim(spec, mine[0], 2);

        let mut siege = Siege::default();
        siege.advance(
            spec,
            &territory,
            &[
                Push { tile, team: 0, strength: HOLD * 0.4 },
                Push { tile, team: 2, strength: HOLD * 0.1 },
            ],
            1.0,
        );
        let (team, part) = siege.front(spec, &territory, tile).expect("a siege is under way");
        assert_eq!(team, 0, "the heavier side is the one besieging");

        // Side 2 comes back stronger: the siege is theirs and starts over, so
        // the tile is less far along than it was a moment ago.
        siege.advance(
            spec,
            &territory,
            &[Push { tile, team: 2, strength: HOLD * 0.2 }],
            1.0,
        );
        let (team, after) = siege.front(spec, &territory, tile).expect("still under way");
        assert_eq!(team, 2, "the siege changed hands");
        assert!(after < part, "and began again rather than inheriting");
    }
}
