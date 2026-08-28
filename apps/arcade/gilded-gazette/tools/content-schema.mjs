/**
 * Schemas for everything authored as MDX under shared/data.
 *
 * &why -> a mistyped trigger or a missing field would not crash anything; the
 *         article would just never print and the passenger would just never
 *         appear. Validation at compile time turns that into a build error.
 * &one -> both runtimes read the compiled output, so this is the only place the
 *         shape of game content is stated
 */
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// &resolve -> zod is a devDependency of vite/, and this file sits in tools/, so
//             node would look in a repo-root node_modules that does not exist.
//             One install location, resolved explicitly, beats a second one.
const require = createRequire(
  join(dirname(fileURLToPath(import.meta.url)), '../vite/package.json'),
);
const { z } = require('zod');

const clock = z
  .string()
  .regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'expected an in-world time like "23:00"');

/**
 * Prose compiled from the MDX body.
 * &split -> everything before the first `##` is the lede and its follow-on
 *           paragraphs; each heading becomes an addressable section, so game
 *           code asks for `sections.alibi` instead of parsing a blob
 */
const section = z.object({
  heading: z.string().min(1),
  paragraphs: z.array(z.string()),
  bullets: z.array(z.string()),
});

const prose = {
  lede: z.string().min(1),
  body: z.array(z.string()),
  sections: z.record(z.string(), section).default({}),
};

/**
 * Where someone can be, as a locations id.
 *
 * &ref -> not an enum. A room is authored under shared/data/locations, so the
 *         vocabulary IS the collection and gen-content checks every location
 *         against it the way it already checks item.owner. A room spelt wrong
 *         is a build error naming the file, not a passenger who quietly never
 *         appears.
 */
const locationId = z.string().min(1);

export const article = z.object({
  id: z.string().min(1),
  when: z
    .object({
      boot: z.boolean().optional(),
      level: z.string().optional(),
      after: clock.optional(),
      before: clock.optional(),
    })
    .refine((w) => w.boot !== undefined || w.level !== undefined, {
      message: 'when: needs at least a boot or a level, or nothing can print it',
    }),
  priority: z.number().int().default(0),
  kicker: z.string().min(1),
  title: z.string().min(1),
  caption: z.string().min(1),
  ...prose,
});

export const passenger = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  /** How the passenger list prints them; defaults to the name. */
  listed: z.string().optional(),
  role: z.string().min(1),
  berth: z.string().min(1),
  boarded: z.object({ at: clock, where: z.string().min(1) }),
  /** Where they are found when nothing else has moved them. */
  location: locationId,
  /**
   * &derived -> stamped on by gen-content, not authored. The night draws its culprit
   *          from everybody aboard who is not the body, so a suspect is exactly that
   *          and authoring it separately only creates a second answer that can drift
   *          from the first -- which it had: three passengers were marked while the
   *          draw was picking from seven.
   */
  suspect: z.boolean().optional(),
  /**
   * The one this is all about. A victim is a passenger and not a collection of
   * their own: they bought a ticket, they have a berth, and their evening runs
   * like anyone's until it stops. What makes them the victim is that it stops.
   *
   * &exclusive -> gen-content enforces exactly one, and that they are not also a
   *           suspect. Two bodies is a different game and nobody murders
   *           themselves in this one.
   */
  victim: z.boolean().default(false),
  /** Short, playable descriptors an NPC system can branch on. */
  traits: z.array(z.string()).default([]),
  relationships: z
    .array(z.object({ who: z.string().min(1), tie: z.string().min(1) }))
    .default([]),
  /**
   * The same statements the `## Alibi` bullets make, in the form a generator can
   * respect. Constraints, not prose: the words are already written next door, and
   * the pair is the point -- one is what he says, this is what it would mean.
   *
   * &honest -> a run places everybody consistently with their OWN claims and then
   *           breaks exactly one, for the culprit. Without that the generator makes
   *           liars of people at random, several passengers contradict themselves
   *           for no reason, and contradiction stops identifying anybody.
   * &positional -> only claims about where somebody was. "Says she has never met
   *           Dr. Weiss" is a claim about a person and stays prose; nothing can
   *           place a passenger to satisfy it.
   */
  claims: z
    .array(
      z
        .object({
          where: locationId,
          /** Denies ever having been there, for the whole journey. */
          never: z.boolean().default(false),
          /**
           * The window they place themselves in that room for, and they mean the
           * whole of it. `from` alone runs to the end of the journey, `until` alone
           * from the moment they boarded. One reading, because two would make a
           * claim mean something different depending on which half was written.
           */
          from: clock.optional(),
          until: clock.optional(),
        })
        .refine((c) => !(c.never && (c.from || c.until)), {
          message: 'a never claim covers the whole journey, so it takes no from/until',
        }),
    )
    .default([]),
  /**
   * What it looks like to find this passenger in a given room, and -- because a
   * passenger can only be put somewhere there is a line for them -- which rooms
   * they can be in at all. The guard's van is locked; two people have a line for it.
   *
   * &authored -> drawn from, never composed. A room's worth of lines is written by
   *           hand so that a generated night still reads like somebody wrote it,
   *           which a template never does.
   */
  sightings: z.record(locationId, z.array(z.string().min(1)).min(1)).default({}),
  ...prose,
});

/**
 * A spot in a carriage, in carriage-local metres.
 *
 * Not world space. Consist centres itself on its own origin, so inserting a
 * carriage moves every world X by half a pitch, and anything authored in world
 * space slides half a car every time the train changes length. Local placement
 * is what survives the consist growing, which is the whole reason for the field.
 *
 * `along` runs down the train from the carriage centre, `across` from the aisle
 * centreline toward a wall, `above` lifts it off the deck so a plate can stand on
 * a table rather than under it, and `facing` turns it about its own up axis.
 * Every model this game loads has its origin on the ground under it, so `above`
 * is the height of whatever surface the thing is standing on and nothing else.
 * The carriage geometry those have to clear -- end walls, door swing, the aisle
 * between the benches -- is checked engine side against the measured constants
 * on Consist rather than restated here, because a second copy of 8.615 is a
 * second copy that can drift.
 */
const placement = z.object({
  along: z.number(),
  across: z.number(),
  above: z.number().min(0).default(0),
  facing: z.number().default(0),
});

export const item = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  kind: z.enum(['document', 'key', 'personal', 'weapon', 'curio']),
  /** Present in the player's effects from the start. */
  carried: z.boolean().default(false),
  /** Passenger id this belongs to, when it is not the player's. */
  owner: z.string().optional(),
  /** Where it is found, when it is not carried. */
  location: locationId.optional(),
  /**
   * The glb under godot/assets/items that is this thing, without the extension.
   *
   * Named rather than derived from the id, because one model can be several
   * items -- two identical candlesticks in two rooms are two ids -- and because
   * an id is content vocabulary while a filename is an asset that gets rebuilt.
   */
  model: z.string().min(1).optional(),
  /**
   * Where it lies in its room. Absent means the item is real but has nowhere to
   * be seen yet, which is every item this game shipped with before the first
   * one had a model.
   */
  found: placement.optional(),
  /** Reading it, opening it or turning it over reveals this. */
  reveals: z.array(z.string()).default([]),
  ...prose,
})
  /**
   * &lying -> a thing on the floor of a room needs all three of a model to draw,
   *           a room to be in, and a spot in that room. Any one of them alone is
   *           an item that either never appears or appears in the wrong carriage,
   *           and both of those read as a broken build rather than a content gap.
   */
  .refine((i) => !(i.found || i.model) || (i.found && i.model && i.location), {
    message: 'found/model: an item in the world needs a model, a location and a found spot',
  })
  /**
   * &pockets -> a carried item is in the player's effects, so a copy of it lying
   *             in a room as well would be the same object in two places.
   */
  .refine((i) => !(i.carried && i.found), {
    message: 'found: a carried item cannot also be lying in a room',
  });

/**
 * Somewhere on the train, or off it.
 *
 * &carriage -> a location with a carriage index is a place in the consist, at
 *         position along the train; SOccupancy resolves a world position into
 *              that one. Without it the location is off the train, so nobody
 *         and the ECS never spawns a carriage for it.
 */
/**
 * One prop standing in a room, at a spot in its carriage.
 */
const furnishing = placement.extend({
  prop: z.string().min(1),
  /** Stamped on by gen-content from the prop library; not authored per room. */
  seats: z.boolean().optional(),
  cushionHeight: z.number().optional(),
});

/**
 * A sheet posted on a carriage wall, and where it hangs.
 *
 * &wall -> placed the way a furnishing is, in carriage-local metres, for the same
 *          reason: the consist moves every world X when it changes length. `along`
 *          runs down the train from the carriage centre and `side` picks which wall,
 *          because a notice is on a wall rather than standing on the floor and the
 *          across is therefore the wall, not a free number.
 * &image -> the basename tools/gen-itch-art.py writes, without extension. The same
 *           sheet is printed three sizes: the store page, the modal, and the texture
 *           the poster in the world wears.
 */
export const notice = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  image: z.string().min(1),
  carriage: z.number().int().min(0),
  along: z.number(),
  side: z.union([z.literal(1), z.literal(-1)]),
  /**
   * Metres above the deck to the middle of the sheet.
   *
   * The default clears the seat backs, which stand 1.33 above the floor: a sheet at
   * head height is a sheet the bench in front of it hides from everywhere but the
   * seat it is behind. Posted between the windows, it is read from the aisle.
   */
  above: z.number().min(0).default(1.95),
  /** Printed width in metres; the height follows the image's own aspect. */
  width: z.number().min(0.1).default(0.8),
  ...prose,
});

export const location = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  carriage: z.number().int().min(0).optional(),
  /** What stands in the room, for a location that is a place in the consist. */
  furnishings: z.array(furnishing).default([]),
  ...prose,
});

/**
 * Directory name under shared/data -> schema for every .mdx inside it.
 *
 * &order -> locations first; every other collection points into it, so it has
 *           to be compiled before the references can be checked
 */
export const collections = {
  locations: location,
  articles: article,
  passengers: passenger,
  items: item,
  notices: notice,
};
