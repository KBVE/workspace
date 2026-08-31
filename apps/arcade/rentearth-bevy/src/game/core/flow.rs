//! Where to go next, worked out once for the whole map.
//!
//! The alternative is a search per mover, and that is the shape of pathing
//! that does not survive the numbers this game is built for: a hundred
//! thousand searches a frame is a hundred thousand searches a frame however
//! fast each one is. One field is one breadth-first walk over twenty-odd
//! thousand tiles, and everything heading to the same place reads it for free.
//!
//! It is also what makes a crowd going round an obstacle look like a crowd
//! rather than like a hundred movers each solving the obstacle privately.
//!
//! What may be crossed is the caller's business, which is the whole reason
//! this lives here rather than beside the men who first needed it. An army
//! and a fleet want the same walk over the same hexes and disagree about
//! exactly one predicate -- and two copies of a breadth-first search stay
//! equal for exactly as long as nobody edits one of them.

use crate::game::core::map::{MapSpec, Offset};

/// No step from here: arrived, unreachable, or ground this field does not
/// cross.
pub const NOWHERE: u8 = 6;

/// Where one body is going, as one answer per tile.
///
/// `step[tile]` is which of that tile's six neighbours to move to, so a mover
/// asks one question -- "from here, which way?" -- and never looks further
/// than its own hex.
pub struct FlowField {
    pub goal: Offset,
    step: Vec<u8>,
    /// What the field was built for, so it is rebuilt when that changes and
    /// not otherwise.
    built_for: Option<Offset>,
}

impl FlowField {
    /// An unbuilt field aimed somewhere.
    ///
    /// Nothing is walked here. A field raised during play is filled in by the
    /// next [`FlowField::rebuild`], which is the same path every other change
    /// of goal takes -- so there is one place where the walk happens rather
    /// than two that have to agree.
    pub fn to(goal: Offset) -> Self {
        Self {
            goal,
            step: Vec::new(),
            built_for: None,
        }
    }

    /// Every tile pointing the same way.
    ///
    /// Not a field any map produces. It exists so that movement can be tested
    /// against a known answer without standing a map up first, which is the
    /// difference between testing the walking and testing the search.
    #[cfg(test)]
    pub fn uniform(goal: Offset, spec: MapSpec, dir: u8) -> Self {
        Self {
            goal,
            step: vec![dir; spec.tile_count() as usize],
            built_for: Some(goal),
        }
    }

    /// Whether the walk has been done yet.
    ///
    /// A field raised this frame has no steps in it, which is indistinguishable
    /// from a field whose goal nothing can reach -- and a mover that cannot
    /// tell those apart gives up on an order the instant it is given one.
    pub fn ready(&self) -> bool {
        self.built_for.is_some()
    }

    /// Which neighbour to move to from here, if anywhere.
    pub fn at(&self, spec: MapSpec, tile: Offset) -> Option<usize> {
        match self.step.get(tile.wrapped(spec).index(spec)).copied() {
            Some(NOWHERE) | None => None,
            Some(dir) => Some(dir as usize),
        }
    }

    /// Work the field out, if the goal has moved since it last was.
    ///
    /// Breadth first rather than Dijkstra because every step between
    /// neighbouring hexes costs the same. When terrain starts costing
    /// different amounts to cross this becomes a priority queue and nothing
    /// else about it changes.
    pub fn rebuild(&mut self, spec: MapSpec, passable: impl Fn(Offset) -> bool) {
        if self.built_for == Some(self.goal) {
            return;
        }
        self.step = build(spec, self.goal, passable);
        self.built_for = Some(self.goal);
    }
}

/// Walk outward from the goal, writing at each tile the way back toward it.
fn build(spec: MapSpec, goal: Offset, passable: impl Fn(Offset) -> bool) -> Vec<u8> {
    let tiles = spec.tile_count() as usize;
    let mut step = vec![NOWHERE; tiles];
    let mut seen = vec![false; tiles];

    let goal = goal.wrapped(spec);
    if !passable(goal) {
        return step;
    }

    let mut queue = std::collections::VecDeque::with_capacity(tiles / 4);
    seen[goal.index(spec)] = true;
    queue.push_back(goal);

    while let Some(tile) = queue.pop_front() {
        // Walking outward from the goal, so the neighbour is the one being
        // reached and the step it wants is the one back toward here -- which
        // is that neighbour's own index for the tile we came from.
        for (dir, raw) in tile.neighbours().into_iter().enumerate() {
            let next = raw.wrapped(spec);
            let index = next.index(spec);
            if seen[index] || !passable(next) {
                continue;
            }
            seen[index] = true;
            // The way back is the opposite of the way out. The neighbour table
            // is laid out in opposing pairs, so the reverse of a direction is
            // its partner: 0<->1, 2<->5, 3<->4.
            step[index] = match dir {
                0 => 1,
                1 => 0,
                2 => 5,
                3 => 4,
                4 => 3,
                _ => 2,
            };
            queue.push_back(next);
        }
    }

    step
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec() -> MapSpec {
        MapSpec {
            cols: 8,
            rows: 8,
            ..MapSpec::default()
        }
    }

    /// Following the steps from anywhere reachable has to end at the goal.
    /// A field that pointed the wrong way would still be a field -- every
    /// tile would have an answer, and every answer would be wrong.
    #[test]
    fn every_step_leads_to_the_goal() {
        let spec = spec();
        let goal = Offset { col: 2, row: 3 };
        let mut field = FlowField::to(goal);
        field.rebuild(spec, |_| true);

        for tile in spec.tiles() {
            let mut at = tile;
            for _ in 0..spec.tile_count() {
                let Some(dir) = field.at(spec, at) else { break };
                at = at.neighbours()[dir].wrapped(spec);
            }
            assert_eq!(at, goal, "{tile:?} did not arrive");
        }
    }

    /// A field is only as good as its predicate, so the predicate has to
    /// actually stop it: a wall that gets crossed is a fleet sailing overland.
    #[test]
    fn impassable_tiles_are_never_stepped_onto() {
        let spec = spec();
        let goal = Offset { col: 0, row: 0 };
        let blocked = |tile: Offset| tile.col != 4;

        let mut field = FlowField::to(goal);
        field.rebuild(spec, blocked);

        for tile in spec.tiles() {
            let Some(dir) = field.at(spec, tile) else {
                continue;
            };
            let next = tile.neighbours()[dir].wrapped(spec);
            assert!(blocked(next), "stepped onto {next:?}");
        }
    }

    /// An unreachable goal must give nobody a step, rather than giving
    /// everybody a step into the thing they cannot cross.
    #[test]
    fn a_goal_nothing_can_reach_gives_no_steps() {
        let spec = spec();
        let mut field = FlowField::to(Offset { col: 4, row: 4 });
        field.rebuild(spec, |tile| tile.col != 4);

        assert!(spec.tiles().all(|tile| field.at(spec, tile).is_none()));
    }
}
