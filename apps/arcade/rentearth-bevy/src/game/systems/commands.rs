//! The order menu.
//!
//! Every standing order used to be a bare key: [P] patrolled, [X] disbanded,
//! [C] turned soldiers into citizens for good. That is fine until a hand
//! resting on the keyboard dissolves a group, and there is no undo for men who
//! have stopped being men.
//!
//! So the keys are behind a menu. [Space] opens it on whatever is selected,
//! the same letters do the same things while it is open, and nothing else
//! listens for them. The menu is also the only list of what a group can be
//! told to do, which is the other thing bare keys were bad at: a command you
//! cannot see is a command nobody uses.
//!
//! What the menu produces is a message rather than a call. The systems that
//! carry these out live behind the encrypted half of the game -- they need the
//! unit array -- and a menu that named them would not build without the key.

use bevy::prelude::*;
use bevy::text::FontSize;

use crate::game::components::command::{DragBox, Group, Selected};
use crate::game::core::terrain::SEA_LEVEL;

// The drag box.
//
// Selection by dragging a rectangle lives here rather than with the men, and
// not only because the ships wanted it too. The box is one thing the pointer
// owns and several things read, and the reader that also *cleared* it decided,
// by whichever order the schedule happened to pick, whether anybody else saw
// the drag at all. Every reader now runs in `ReadDrag` and the box is emptied
// once, afterwards, by the plugin that owns it.

/// Below this a drag is a click.
///
/// Without it, every click is a drag of a pixel or two -- whatever the mouse
/// moved between press and release -- and a box that small selects whatever
/// happens to be under one pixel, which is not what the hand meant.
pub const DRAG_MINIMUM: f32 = 6.0;

/// Everything that reads a finished drag.
///
/// A set rather than an ordering between named systems, because the readers
/// are in optional modules: with the units feature off there is no
/// `take_selection` for anything to run before, and a schedule that named it
/// would not build.
#[derive(SystemSet, Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct ReadDrag;

/// Where a screen point lands on the ground.
///
/// Public because everything that turns a pointer into a place needs it, and
/// two answers to "what is under the cursor" is a game where the box selects
/// one tile and the order goes to another.
pub fn ground_at(
    camera: &Camera,
    camera_transform: &GlobalTransform,
    screen: Vec2,
) -> Option<Vec3> {
    let ray = camera.viewport_to_world(camera_transform, screen).ok()?;
    let distance = ray.intersect_plane(
        Vec3::new(0.0, SEA_LEVEL, 0.0),
        InfinitePlane3d::new(Vec3::Y),
    )?;
    Some(ray.get_point(distance))
}

/// The rectangle, while it is being dragged.
#[derive(Component)]
struct DragRectangle;

fn spawn_rectangle(mut commands: Commands) {
    commands.spawn((
        Node {
            position_type: PositionType::Absolute,
            border: UiRect::all(Val::Px(1.0)),
            ..default()
        },
        BorderColor::all(Color::srgba(0.85, 0.90, 0.95, 0.9)),
        // Faint enough to see the ground being selected through it.
        BackgroundColor(Color::srgba(0.60, 0.75, 0.95, 0.12)),
        Visibility::Hidden,
        DragRectangle,
    ));
}

/// Follow the mouse: press starts a drag, release ends it.
fn drag(
    buttons: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    mut box_: ResMut<DragBox>,
) {
    let Some(cursor) = windows.iter().find_map(|w| w.cursor_position()) else {
        return;
    };

    if buttons.just_pressed(MouseButton::Left) {
        box_.from = Some(cursor);
    }
    box_.to = cursor;
}

/// Draw it while the button is down.
fn show_rectangle(
    box_: Res<DragBox>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut rectangle: Query<(&mut Node, &mut Visibility), With<DragRectangle>>,
) {
    let Ok((mut node, mut visibility)) = rectangle.single_mut() else {
        return;
    };

    let drawn = buttons.pressed(MouseButton::Left)
        && box_
            .rect()
            .is_some_and(|(low, high)| (high - low).length() >= DRAG_MINIMUM);

    let Some((low, high)) = box_.rect().filter(|_| drawn) else {
        *visibility = Visibility::Hidden;
        return;
    };

    *visibility = Visibility::Visible;
    node.left = Val::Px(low.x);
    node.top = Val::Px(low.y);
    node.width = Val::Px(high.x - low.x);
    node.height = Val::Px(high.y - low.y);
}

/// Put the box away, once everyone who wanted it has had it.
fn end_drag(buttons: Res<ButtonInput<MouseButton>>, mut box_: ResMut<DragBox>) {
    if buttons.just_released(MouseButton::Left) {
        box_.from = None;
    }
}

/// Something a player can tell a group to do.
#[derive(Message, Clone, Copy, PartialEq, Eq, Debug)]
pub enum GroupCommand {
    /// Walk the border, round and round.
    Patrol,
    /// Hold the ground you are on.
    Guard,
    /// Come home and be quartered in the city.
    Recall,
    /// Turn the garrison back out of the gate.
    Sally,
    /// Break up; the men go back to the field army.
    Disband,
    /// Into the city for good, as people rather than soldiers.
    Citizens,
}

/// The whole menu, in the order it is shown.
///
/// One table rather than a match arm in each of the drawing and the reading:
/// a letter that meant one thing on screen and another to the keyboard is
/// exactly the accident this was built to stop.
const MENU: [(KeyCode, &str, GroupCommand, bool); 6] = [
    (KeyCode::KeyP, "P  patrol border", GroupCommand::Patrol, false),
    (KeyCode::KeyF, "F  guard ground", GroupCommand::Guard, false),
    (KeyCode::KeyR, "R  recall to city", GroupCommand::Recall, false),
    (KeyCode::KeyV, "V  sally garrison", GroupCommand::Sally, false),
    (KeyCode::KeyX, "X  disband", GroupCommand::Disband, true),
    (
        KeyCode::KeyC,
        "C  settle as citizens",
        GroupCommand::Citizens,
        true,
    ),
];

/// Whether the menu is up.
#[derive(Resource, Default)]
pub struct CommandMenu {
    pub open: bool,
}

#[derive(Component)]
struct MenuPanel;

fn spawn_menu(mut commands: Commands) {
    commands.spawn((
        Text::new(String::new()),
        TextFont {
            font_size: FontSize::Px(14.0),
            ..default()
        },
        TextColor(Color::srgb(0.94, 0.96, 0.99)),
        Node {
            position_type: PositionType::Absolute,
            bottom: Val::Px(16.0),
            left: Val::Px(16.0),
            padding: UiRect::all(Val::Px(10.0)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.02, 0.03, 0.05, 0.82)),
        Visibility::Hidden,
        MenuPanel,
    ));
}

/// [Space] opens it, [Escape] shuts it, and choosing anything shuts it too.
///
/// Nothing opens without a selection: a menu of orders with nobody to give
/// them to is a menu of nothing, and shutting it again is one more key the
/// player did not need to press.
fn work_the_menu(
    keys: Res<ButtonInput<KeyCode>>,
    selected: Query<(), With<Selected>>,
    mut menu: ResMut<CommandMenu>,
    mut orders: MessageWriter<GroupCommand>,
) {
    if keys.just_pressed(KeyCode::Escape) {
        menu.open = false;
        return;
    }

    if keys.just_pressed(KeyCode::Space) {
        menu.open = !menu.open && !selected.is_empty();
        return;
    }

    if !menu.open {
        return;
    }

    for (key, _, command, _) in MENU {
        if keys.just_pressed(key) {
            orders.write(command);
            menu.open = false;
            return;
        }
    }
}

/// Draw it, and say who it is talking about.
fn show_menu(
    menu: Res<CommandMenu>,
    groups: Query<&Group, With<Selected>>,
    selected: Query<(), With<Selected>>,
    mut panel: Query<(&mut Text, &mut Visibility), With<MenuPanel>>,
) {
    let Ok((mut text, mut visibility)) = panel.single_mut() else {
        return;
    };

    if !menu.open || selected.is_empty() {
        *visibility = Visibility::Hidden;
        return;
    }
    *visibility = Visibility::Visible;

    // Named if it has a number, counted if it does not: a drag-selection is
    // not a group yet, and telling the player he is ordering "group" when he
    // has not made one would be a lie in the one place he is checking.
    let heading = match groups.iter().next() {
        Some(group) => format!("group {{{}}}  {} men", group.number, group.strength),
        None => match selected.iter().count() {
            1 => "1 company selected".to_string(),
            many => format!("{many} companies selected"),
        },
    };

    let listed: Vec<String> = MENU
        .iter()
        .map(|(_, label, _, grave)| match grave {
            // The two that cannot be taken back are marked as such. Men who
            // have become citizens do not come back out, and a disbanded
            // group's number is spent.
            true => format!("{label}   (final)"),
            false => label.to_string(),
        })
        .collect();

    **text = format!(
        "{heading}\n{}\n\nesc  close",
        listed.join("\n"),
    );
}

/// A hint that the menu exists, shown whenever anything is selected.
///
/// Without it the menu is a secret, which is the same failure as a bare key
/// with better manners.
fn show_hint(
    menu: Res<CommandMenu>,
    selected: Query<(), With<Selected>>,
    mut panel: Query<(&mut Text, &mut Visibility), With<MenuPanel>>,
) {
    if menu.open || selected.is_empty() {
        return;
    }
    let Ok((mut text, mut visibility)) = panel.single_mut() else {
        return;
    };

    *visibility = Visibility::Visible;
    **text = "space  orders".to_string();
}

/// Hold the menu open from the environment, so it can be photographed.
///
/// The same trick the museum and the selection use: the interesting state is
/// behind a key, and a screenshot has no hands.
///
/// ```text
/// RENTEARTH_MENU=1 moon run rentearth-bevy:run
/// ```
fn menu_from_env(mut menu: ResMut<CommandMenu>) {
    if std::env::var("RENTEARTH_MENU").is_ok() {
        menu.open = true;
    }
}

pub struct CommandsPlugin;

impl Plugin for CommandsPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CommandMenu>()
            .init_resource::<DragBox>()
            .add_message::<GroupCommand>()
            .add_systems(Startup, (spawn_menu, spawn_rectangle))
            .add_systems(
                Update,
                (menu_from_env, work_the_menu, show_menu, show_hint).chain(),
            )
            .add_systems(Update, (drag, show_rectangle).chain().before(ReadDrag))
            .add_systems(Update, end_drag.after(ReadDrag));
    }
}
