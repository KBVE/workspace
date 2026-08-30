//! Who commands what.
//!
//! These are components, where `Unit` deliberately is not. The difference is
//! how many there are: a hundred thousand men cannot each be an entity
//! carrying a transform and a visibility computation, but the sides, their
//! homes and the bodies they are organised into number in the dozens. Those
//! are exactly what an ECS is for, and holding them in flat arrays instead
//! would be the same mistake in the other direction.
//!
//! The split also matches how the game is played. Nobody orders a hundred
//! thousand men one at a time -- they order companies, and a company is few
//! enough to be an entity with a queue of intentions hanging off it.

use bevy::prelude::*;

use crate::game::core::map::Offset;

/// Which side something belongs to.
///
/// A component here and a plain field on `Unit`, which is not a contradiction:
/// the same fact is worth indexing on an entity and worth packing into a byte
/// a hundred thousand times over.
#[derive(Component, Clone, Copy, PartialEq, Eq, Debug)]
pub struct Team(pub u32);

/// A side in the game.
///
/// One of these is a person and the rest are not, and that is the only thing
/// that distinguishes them -- an AI that cannot be swapped in for the player
/// is an AI playing a different game.
#[derive(Component, Clone, Copy, Debug)]
pub struct Player {
    pub human: bool,
}

/// Somewhere a side grows men.
///
/// Its own entity rather than an entry in the bases array, because a home is
/// going to accumulate things -- what it is building, how fast, what it has
/// stored -- and every one of those is a component waiting to be added rather
/// than another parallel array to keep in step.
#[derive(Component, Clone, Copy, Debug)]
pub struct Home {
    pub tile: Offset,
}

/// How many people live somewhere.
///
/// Hung off a home rather than counted in it, because "a place with people in
/// it" is going to be true of more things than the capital -- a town, a camp,
/// a captured city -- and each of those is this component on another entity
/// rather than another field on `Home`.
///
/// A count rather than the men themselves: a citizen is not a soldier standing
/// still, he is a soldier who stopped being drawn. That is the whole saving,
/// and it is why men can be absorbed by the thousand.
#[derive(Component, Clone, Copy, Default, Debug)]
pub struct Populace {
    pub citizens: u32,
}

/// What a side has put by.
///
/// On the side rather than on the capital, because it is the side that spends
/// it. Wood only for now; stone is the second field and nothing else changes
/// when it arrives, which is the point of it being a struct rather than a
/// number.
#[derive(Component, Clone, Copy, Default, Debug)]
pub struct Stock {
    pub wood: u32,
}

/// A company sent to cut wood, and where it is in the round trip.
///
/// The whole cycle is three facts: which grove, how much is on their backs,
/// and which way they are walking. Held on the company rather than on the men
/// because it is one journey however many are making it -- the same reason an
/// order is one write.
#[derive(Component, Clone, Copy, Debug)]
pub struct Cutting {
    pub grove: Offset,
    pub carrying: u32,
    /// Walking home with a load rather than standing in the trees with an axe.
    pub hauling: bool,
}

impl Cutting {
    pub fn at(grove: Offset) -> Self {
        Self {
            grove,
            carrying: 0,
            hauling: false,
        }
    }
}

/// A body of men under one order.
///
/// The unit of command, as opposed to `Unit`, which is the unit of drawing.
/// Soldiers carry which company they are in; the company carries where it is
/// going. That is what keeps an order one write rather than twenty-five
/// thousand.
#[derive(Component, Clone, Copy, Debug)]
pub struct Company {
    /// This company's number, as its men hold it.
    ///
    /// Carried here as well as in the `Roster` because the men are the other
    /// side of that lookup: matching a soldier to his company needs the number
    /// the soldier has, and reaching it any other way means resolving every
    /// entity back through the table to ask which one this is.
    pub id: u32,
    /// Which flow field this company walks by. Its own rather than its side's,
    /// so that splitting an army in two gives two destinations and not an
    /// argument over one.
    ///
    /// Not the same thing as `id`, however equal the two look while every side
    /// has exactly one company.
    pub field: usize,
}

/// Soldiers held inside a town.
///
/// Not the same thing as `Populace`, and the difference is the whole point:
/// a citizen has stopped being a soldier, a man in the garrison has only
/// stopped being *drawn*. He can be turned out of the gate again as the man
/// he was, which is what makes putting an army indoors a decision rather than
/// a disposal.
#[derive(Component, Clone, Copy, Default, Debug)]
pub struct Garrison {
    pub men: u32,
}

/// A group walking home to be put up in the city.
///
/// A marker rather than a stance, because it ends: the group stops existing
/// when the last of it is through the gate, and a stance that deleted the
/// thing holding it would be a strange kind of standing order.
#[derive(Component, Clone, Copy, Debug)]
pub struct Returning;

/// A numbered body the player made himself, one to nine.
///
/// The number is the whole point: an order given to "that lot over there"
/// needs the player to find them again first, and a key that goes straight to
/// them is the difference between a company he uses and one he loses. Nine
/// because that is how many keys are on the row, which is also why every game
/// that has ever done this stopped at nine.
///
/// Strength is carried here rather than counted where it is shown: the men
/// live in an array behind the encrypted half of the game, and the readout
/// that displays this must build without it.
#[derive(Component, Clone, Copy, Debug)]
pub struct Group {
    pub number: u32,
    pub strength: u32,
}

/// What a body of men does when it has not been told anything else.
///
/// Standing orders rather than orders: an order is a place to walk to and is
/// finished on arrival, a stance is what they do for as long as they hold it.
/// That distinction is what makes a group worth having a number -- otherwise
/// every one of them needs the player's attention every time it arrives
/// somewhere.
#[derive(Component, Clone, Copy, Default, PartialEq, Eq, Debug)]
pub enum Stance {
    /// Waiting to be told. The state a group is made in.
    #[default]
    Ready,
    /// Walking the edge of what the side holds, round and round.
    Patrol,
    /// Holding the ground they are standing on and not being drawn off it.
    Guard,
}

impl Stance {
    /// The one letter it shows as, so a group reads as `{1} P`.
    pub fn badge(self) -> char {
        match self {
            Stance::Ready => '-',
            Stance::Patrol => 'P',
            Stance::Guard => 'G',
        }
    }
}

/// Where a company has been told to go, in the order it was told.
///
/// A queue rather than a destination, because that is the difference between
/// "go here" and "go here, then there" -- and because a real-time game with no
/// queue makes the player the queue.
#[derive(Component, Default, Debug)]
pub struct Orders {
    pub waypoints: Vec<Offset>,
}

impl Orders {
    /// Replace whatever was ordered. A plain click.
    pub fn go(&mut self, tile: Offset) {
        self.waypoints.clear();
        self.waypoints.push(tile);
    }

    /// Add to what was ordered. The same click with shift held.
    pub fn then(&mut self, tile: Offset) {
        self.waypoints.push(tile);
    }

    /// Where the company is heading right now.
    pub fn current(&self) -> Option<Offset> {
        self.waypoints.first().copied()
    }

    /// Arrived. Returns whether anything is left to do.
    pub fn reached(&mut self) -> bool {
        if !self.waypoints.is_empty() {
            self.waypoints.remove(0);
        }
        !self.waypoints.is_empty()
    }
}

/// Company number to entity.
///
/// Soldiers hold a number rather than an `Entity` -- four bytes against eight,
/// a hundred thousand times -- so something has to turn one into the other.
/// This is that, and it is the price of the saving: a number is only as good
/// as the table that resolves it.
#[derive(Resource, Default)]
pub struct Roster(pub Vec<Entity>);

impl Roster {
    pub fn entity(&self, company: u32) -> Option<Entity> {
        self.0
            .get(company as usize)
            .copied()
            .filter(|entity| *entity != Entity::PLACEHOLDER)
    }

    /// A company that no longer exists.
    ///
    /// Its slot stays where it is rather than being removed, because a
    /// soldier holds his company as an index and shuffling the table would
    /// hand every man behind the gap to somebody else's orders. The number is
    /// simply spent -- there are thirty-two, and reusing them is a problem
    /// for the day a game gets through that many.
    pub fn retire(&mut self, company: u32) {
        if let Some(slot) = self.0.get_mut(company as usize) {
            *slot = Entity::PLACEHOLDER;
        }
    }

    /// Enrol a company and hand back its number.
    pub fn enrol(&mut self, entity: Entity) -> u32 {
        self.0.push(entity);
        (self.0.len() - 1) as u32
    }
}

/// Which men the last selection actually caught, as indices into the unit
/// array.
///
/// Selection names companies, because a company is what an order is given to.
/// But a squad is made out of *men*, and which men were inside the box is a
/// fact the box knew and the company does not -- so it is kept here rather
/// than worked out again later from a rectangle nobody remembers.
///
/// Indices rather than anything sturdier because they are used within a frame
/// or two of being taken, and because the alternative is an identifier per man
/// at a hundred thousand men.
#[derive(Resource, Default, Debug)]
pub struct Picked(pub Vec<usize>);

/// Picked out by the player.
///
/// A marker rather than a list held somewhere central: "what is selected" is
/// then a query rather than a thing to keep in step with the world, and a
/// company that stops existing stops being selected without anyone tidying up
/// after it.
#[derive(Component, Clone, Copy, Debug)]
pub struct Selected;

/// A drag in progress, in screen coordinates.
///
/// Screen rather than world because that is both where the mouse gives it and
/// where the rectangle is drawn. Its corners are put on the ground once, when
/// the selection is made, rather than every frame -- and the conversion is
/// exact rather than approximate, because the camera never yaws.
///
/// A resource because there is only ever one, and it belongs to the pointer
/// rather than to anything in the world.
#[derive(Resource, Default, Debug)]
pub struct DragBox {
    pub from: Option<Vec2>,
    pub to: Vec2,
}

impl DragBox {
    /// The rectangle covered, smallest corner first, if a drag is under way.
    pub fn rect(&self) -> Option<(Vec2, Vec2)> {
        let from = self.from?;
        Some((from.min(self.to), from.max(self.to)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tile(col: i32, row: i32) -> Offset {
        Offset { col, row }
    }

    /// A click replaces and a shift-click appends. Getting these the same way
    /// round would make every order cancel the last one, or make none of them
    /// cancel anything.
    #[test]
    fn orders_queue_in_the_order_given() {
        let mut orders = Orders::default();

        orders.go(tile(1, 1));
        orders.then(tile(2, 2));
        assert_eq!(orders.current(), Some(tile(1, 1)));

        assert!(orders.reached(), "the second waypoint went missing");
        assert_eq!(orders.current(), Some(tile(2, 2)));

        assert!(!orders.reached());
        assert_eq!(orders.current(), None);

        orders.go(tile(3, 3));
        orders.go(tile(4, 4));
        assert_eq!(orders.waypoints, vec![tile(4, 4)], "a click must replace");
    }

    /// Arriving with nothing ordered must not panic, which is the state every
    /// company sits in for most of its life.
    #[test]
    fn arriving_with_no_orders_is_fine() {
        let mut orders = Orders::default();
        assert!(!orders.reached());
        assert_eq!(orders.current(), None);
    }

    /// A drag is a rectangle whichever corner it started from. Dragging up and
    /// left is the same box as dragging down and right, and a selection that
    /// only worked one way would look like it worked until someone dragged the
    /// other.
    #[test]
    fn a_drag_is_the_same_box_either_way() {
        let mut drag = DragBox::default();
        assert_eq!(drag.rect(), None);

        drag.from = Some(Vec2::new(10.0, 20.0));
        drag.to = Vec2::new(-5.0, 4.0);

        assert_eq!(
            drag.rect(),
            Some((Vec2::new(-5.0, 4.0), Vec2::new(10.0, 20.0))),
        );
    }
}
