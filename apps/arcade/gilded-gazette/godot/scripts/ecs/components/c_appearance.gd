extends ECSComponent
class_name CAppearance

## CAppearance is what a character looks like, as data. Nothing here is a node or a
## resource: [SCastBody] turns it into a [CharacterRig] when the carriage it belongs
## to comes into view, and throws the rig away again when it does not.
##
## Keys index [Wardrobe]. Authored for the cast, whose clothes are evidence, and
## rolled from [member character_seed] for everyone else.

## Key into [constant Wardrobe.BODIES].
var body: StringName = &"regular_male"

## Key into [constant Wardrobe.OUTFITS]: the suit the coat came from, which is also
## the only suit whose accessories this character may wear. The other garments can be
## from any suit in the same group, so this names where they are read from, not what
## every slot holds.
var outfit: StringName = &"male_peasant"

## Slot to library-relative model, for the four covering slots. Rolled a garment at a
## time within one group, so a coat and the trousers under it need not be the same
## suit, and cannot be a suit that would look like a costume change at the waist.
var parts: Dictionary = {}

## Key into [constant Wardrobe.HAIR], or empty for none. Cleared when something worn
## on the head would grow through it.
var hair: StringName = &""

## Key into [constant Wardrobe.BEARDS], or empty for none.
var beard: StringName = &""

## Slot to library-relative model, for whatever is worn over the outfit. Keyed by slot
## rather than listed, because one shoulder holds one pauldron.
var accessories: Dictionary = {}

## Slot to the colour multiplied into everything in it, [constant Wardrobe.SLOT_SKIN]
## and [constant Wardrobe.SLOT_HAIR] included. A slot with no entry keeps the texture
## as it was authored.
var tints: Dictionary = {}

## Crown to sole, in metres, handed to [member CharacterRig.stature_metres]. Rolled
## within a range the body allows, so a teen is not an adult who came out short.
var stature_metres: float = 1.75

## What [method Wardrobe.roll] was given, kept so a rig can be rebuilt or a placement
## jittered without a second source of randomness.
var character_seed: int = 0
