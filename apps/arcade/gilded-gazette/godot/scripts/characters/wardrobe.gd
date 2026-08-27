class_name Wardrobe

## Wardrobe is the catalogue of every piece a character can be assembled from, and
## the same table the kit builder ships from. Runtime and build step read one list,
## so an outfit cannot roll a piece the export left behind.
##
## The parts are named out by hand rather than derived from the file names, because
## the pack does not keep to one convention: the knight's boots are
## Male_Knight_Feet_Armor for him and Female_Knight_Feet for her, and his legs carry
## an _Armor suffix hers does not.
##
## Everything here is library-relative. [method kit_path] turns one into the path the
## game actually loads, under [constant KIT_DIR], because the Web preset excludes
## res://assets/characters wholesale.

## The places a piece can sit. One piece to a slot: a second in the same slot replaces
## the first rather than fighting it for the same square centimetre of shoulder.
##
## [constant COVERING_SLOTS] is the set an outfit has to fill. Anything not covered is
## bare skin showing through a gap, which is why an outfit is one catalogue entry and
## not four rollable ones.
const SLOT_SKIN := &"skin"
const SLOT_HAIR := &"hair"
const SLOT_BEARD := &"beard"
const SLOT_HEAD := &"head"
const SLOT_NECK := &"neck"
const SLOT_SHOULDERS := &"shoulders"
const SLOT_TORSO := &"torso"
const SLOT_ARMS := &"arms"
const SLOT_LEGS := &"legs"
const SLOT_FEET := &"feet"

const COVERING_SLOTS: Array[StringName] = [SLOT_TORSO, SLOT_ARMS, SLOT_LEGS, SLOT_FEET]

## Where the shared Quaternius library lives. Only tools/build_cast_kit.gd reads from
## here; nothing at runtime does.
const LIBRARY_DIR := "res://assets/characters/quaternius_ubc"

## Where the built cast kit lands, and the only character assets the Web build has.
const KIT_DIR := "res://assets/cast"

## Bodies are heads and necks, not whole bodies. A full body under a full outfit is
## two skinned surfaces a millimetre apart and the skin wins often enough to look
## like a hole in the coat; the outfit's Arms piece reaches the fingertips anyway.
##
## [code]skin_material[/code] is the material the neck and face carry, which is what
## a skin tone is applied to. The mesh node it sits on is named differently in every
## body, so the material is the stable handle.
const BODIES := {
	&"regular_male": {
		"model": "models/Regular_Male_OnlyHead.glb",
		"sex": &"male",
		"skin_material": &"MI_Regular_Male",
		"adult": true,
		"stature_metres": Vector2(1.68, 1.86),
	},
	&"regular_female": {
		"model": "models/Regular_Female_OnlyHead.glb",
		"sex": &"female",
		"skin_material": &"MI_Regular_Female",
		"adult": true,
		"stature_metres": Vector2(1.58, 1.74),
	},
	&"teen_male": {
		"model": "models/Teen_Male_OnlyHead.glb",
		"sex": &"male",
		"skin_material": &"MI_Teen_Male",
		"adult": false,
		"stature_metres": Vector2(1.52, 1.66),
	},
	&"teen_female": {
		"model": "models/Teen_Female_OnlyHead.glb",
		"sex": &"female",
		"skin_material": &"MI_Teen_Female",
		"adult": false,
		"stature_metres": Vector2(1.48, 1.62),
	},
}

## Hair is one slot and a beard is another, so a bearded man can still have a parting.
const HAIR := {
	&"simple_parted": {"model": "models/hair/Hair_SimpleParted.glb", "sex": &"any"},
	&"bob": {"model": "models/hair/Hair_Bob.glb", "sex": &"any"},
	&"long": {"model": "models/hair/Hair_Long.glb", "sex": &"any"},
	&"ponytail": {"model": "models/hair/Hair_Ponytail.glb", "sex": &"any"},
}

const BEARDS := {
	&"beard": {"model": "models/hair/Hair_Beard.glb", "sex": &"male"},
}

## What a suit of clothes is, as far as mixing goes. Slots are rolled one at a time
## rather than as a set, because a peasant coat over ranger trousers is a person and a
## set worn whole every time is a uniform.
##
## [code]group[/code] is what may be mixed with what. Within a group the pieces were
## made to sit near each other and do; across one they read as a costume change at the
## waist. [code]whole_set[/code] is for a suit that has to arrive complete: a
## breastplate over a peasant shirt is not a knight down on his luck, it is a mistake.
const STYLES := {
	&"peasant": {"group": &"common"},
	&"ranger": {"group": &"common"},
	&"noble": {"group": &"fine"},
	&"wizard": {"group": &"fine", "crowd": false},
	## Nobody takes an oath at fifteen. Plate on a teen body reads as a child in their
	## father's armour, which is a story this one is not telling.
	&"knight": {"group": &"plate", "whole_set": true, "crowd": false, "adult_only": true},
}

## An outfit is the four covering slots plus whatever it can wear over them. Wear all
## four or the bare skin shows through where a piece is missing, which is why they are
## one entry rather than four rollable slots.
##
## Accessories are rolled over the top and are all optional, so an outfit with none is
## still a complete outfit.
const OUTFITS := {
	&"male_peasant": {
		"sex": &"male",
		"style": &"peasant",
		"parts": {
			SLOT_TORSO: "models/outfits/Male_Peasant_Body.glb",
			SLOT_ARMS: "models/outfits/Male_Peasant_Arms.glb",
			SLOT_LEGS: "models/outfits/Male_Peasant_Legs.glb",
			SLOT_FEET: "models/outfits/Male_Peasant_Feet.glb",
		},
		"accessories": [],
	},
	&"female_peasant": {
		"sex": &"female",
		"style": &"peasant",
		"parts": {
			SLOT_TORSO: "models/outfits/Female_Peasant_Body.glb",
			SLOT_ARMS: "models/outfits/Female_Peasant_Arms.glb",
			SLOT_LEGS: "models/outfits/Female_Peasant_Legs.glb",
			SLOT_FEET: "models/outfits/Female_Peasant_Feet.glb",
		},
		"accessories": [],
	},
	&"male_noble": {
		"sex": &"male",
		"style": &"noble",
		"parts": {
			SLOT_TORSO: "models/outfits/Male_Noble_Body.glb",
			SLOT_ARMS: "models/outfits/Male_Noble_Arms.glb",
			SLOT_LEGS: "models/outfits/Male_Noble_Legs.glb",
			SLOT_FEET: "models/outfits/Male_Noble_Feet.glb",
		},
		"accessories": [
			{"model": "models/outfits/Male_Noble_Acc_Gorget.glb", "slot": SLOT_NECK},
			{"model": "models/outfits/Male_Noble_Acc_Pauldron.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Male_Noble_Acc_Pauldron_Lion.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Male_Noble_Head_Crown.glb", "slot": SLOT_HEAD,
				"hides": [SLOT_HAIR]},
		],
	},
	&"female_noble": {
		"sex": &"female",
		"style": &"noble",
		"parts": {
			SLOT_TORSO: "models/outfits/Female_Noble_Body.glb",
			SLOT_ARMS: "models/outfits/Female_Noble_Arms.glb",
			SLOT_LEGS: "models/outfits/Female_Noble_Legs.glb",
			SLOT_FEET: "models/outfits/Female_Noble_Feet.glb",
		},
		"accessories": [
			{"model": "models/outfits/Female_Noble_Acc_Gorget.glb", "slot": SLOT_NECK},
			{"model": "models/outfits/Female_Noble_Acc_Pauldron.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Female_Noble_Acc_Pauldron_Lion.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Female_Noble_Head_Crown.glb", "slot": SLOT_HEAD,
				"hides": [SLOT_HAIR]},
		],
	},
	&"male_ranger": {
		"sex": &"male",
		"style": &"ranger",
		"parts": {
			SLOT_TORSO: "models/outfits/Male_Ranger_Body.glb",
			SLOT_ARMS: "models/outfits/Male_Ranger_Arms.glb",
			SLOT_LEGS: "models/outfits/Male_Ranger_Legs.glb",
			SLOT_FEET: "models/outfits/Male_Ranger_Feet_Boots.glb",
		},
		"accessories": [
			{"model": "models/outfits/Male_Ranger_Acc_Pauldron.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Male_Ranger_Head_Hood.glb", "slot": SLOT_HEAD,
				"hides": [SLOT_HAIR]},
		],
	},
	&"female_ranger": {
		"sex": &"female",
		"style": &"ranger",
		"parts": {
			SLOT_TORSO: "models/outfits/Female_Ranger_Body.glb",
			SLOT_ARMS: "models/outfits/Female_Ranger_Arms.glb",
			SLOT_LEGS: "models/outfits/Female_Ranger_Legs.glb",
			SLOT_FEET: "models/outfits/Female_Ranger_Feet.glb",
		},
		"accessories": [
			{"model": "models/outfits/Female_Ranger_Acc_Pauldrons.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Female_Ranger_Head_Hood.glb", "slot": SLOT_HEAD,
				"hides": [SLOT_HAIR]},
		],
	},
	&"male_wizard": {
		"sex": &"male",
		"style": &"wizard",
		"parts": {
			SLOT_TORSO: "models/outfits/Male_Wizard_Body.glb",
			SLOT_ARMS: "models/outfits/Male_Wizard_Arms.glb",
			SLOT_LEGS: "models/outfits/Male_Wizard_Legs.glb",
			SLOT_FEET: "models/outfits/Male_Wizard_Feet.glb",
		},
		"accessories": [],
	},
	&"female_wizard": {
		"sex": &"female",
		"style": &"wizard",
		"parts": {
			SLOT_TORSO: "models/outfits/Female_Wizard_Body.glb",
			SLOT_ARMS: "models/outfits/Female_Wizard_Arms.glb",
			SLOT_LEGS: "models/outfits/Female_Wizard_Legs.glb",
			SLOT_FEET: "models/outfits/Female_Wizard_Feet.glb",
		},
		"accessories": [],
	},
	## Plate and cloth are two different torsos of the same suit, not two layers, so
	## the armoured one is a separate outfit rather than an accessory over the other.
	&"male_knight": {
		"sex": &"male",
		"style": &"knight",
		"parts": {
			SLOT_TORSO: "models/outfits/Male_Knight_Body_Armor.glb",
			SLOT_ARMS: "models/outfits/Male_Knight_Arms.glb",
			SLOT_LEGS: "models/outfits/Male_Knight_Legs_Armor.glb",
			SLOT_FEET: "models/outfits/Male_Knight_Feet_Armor.glb",
		},
		"accessories": [
			{"model": "models/outfits/Male_Knight_Acc_Scarf.glb", "slot": SLOT_NECK},
			{"model": "models/outfits/Male_Knight_Acc_Pauldron_Round.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Male_Knight_Acc_Pauldron_Spike.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Male_Knight_Head_Armet.glb", "slot": SLOT_HEAD,
				"hides": [SLOT_HAIR, SLOT_BEARD]},
		],
	},
	&"female_knight": {
		"sex": &"female",
		"style": &"knight",
		"parts": {
			SLOT_TORSO: "models/outfits/Female_Knight_Body_Armor.glb",
			SLOT_ARMS: "models/outfits/Female_Knight_Arms.glb",
			SLOT_LEGS: "models/outfits/Female_Knight_Legs.glb",
			SLOT_FEET: "models/outfits/Female_Knight_Feet.glb",
		},
		"accessories": [
			{"model": "models/outfits/Female_Knight_Acc_Scarf.glb", "slot": SLOT_NECK},
			{"model": "models/outfits/Female_Knight_Acc_Pauldrons_Round.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Female_Knight_Acc_Pauldrons_Spike.glb", "slot": SLOT_SHOULDERS},
			{"model": "models/outfits/Female_Knight_Head_Armet.glb", "slot": SLOT_HEAD,
				"hides": [SLOT_HAIR]},
		],
	},
}

## What the cast kit actually ships, which is not the whole catalogue. Every entry
## here is a few hundred KB of glb plus its share of a texture set in the Web build,
## so this is the line where variety is paid for. The catalogue above stays complete
## so widening the pool is a one-line edit rather than a research trip.
##
## A style marked [code]crowd: false[/code] ships without being rolled. Sworn orders
## and wizardry are rare enough on this line that meeting one at random would spend the
## surprise the story is saving.
const POOL := {
	"bodies": [&"regular_male", &"regular_female", &"teen_female"],
	"outfits": [&"male_peasant", &"female_peasant", &"male_ranger", &"female_ranger",
		&"male_noble", &"female_noble", &"male_knight", &"female_knight"],
	"hair": [&"simple_parted", &"bob", &"long", &"ponytail"],
	"beards": [&"beard"],
}

## A palette is one person's colours, not a colour: a coat, the trousers under it and
## the boots beneath those are three different dyes on a real body, and rolling them
## separately gives a passenger in a green coat and orange trousers.
##
## Kept dull and desaturated. These are travelling clothes under gas lamps, and a
## saturated tint over a texture that already carries colour turns to poster paint.
const PALETTES: Array[Dictionary] = [
	{
		SLOT_TORSO: Color(1.00, 1.00, 1.00),
		SLOT_LEGS: Color(0.86, 0.86, 0.88),
		SLOT_FEET: Color(0.72, 0.66, 0.60),
		"accent": Color(0.78, 0.74, 0.66),
	},
	{
		SLOT_TORSO: Color(0.72, 0.74, 0.82),
		SLOT_LEGS: Color(0.54, 0.56, 0.64),
		SLOT_FEET: Color(0.46, 0.42, 0.40),
		"accent": Color(0.82, 0.80, 0.74),
	},
	{
		SLOT_TORSO: Color(0.85, 0.76, 0.66),
		SLOT_LEGS: Color(0.62, 0.56, 0.48),
		SLOT_FEET: Color(0.50, 0.42, 0.34),
		"accent": Color(0.70, 0.62, 0.46),
	},
	{
		SLOT_TORSO: Color(0.58, 0.64, 0.60),
		SLOT_LEGS: Color(0.44, 0.48, 0.46),
		SLOT_FEET: Color(0.40, 0.36, 0.32),
		"accent": Color(0.76, 0.72, 0.62),
	},
	{
		SLOT_TORSO: Color(0.60, 0.50, 0.50),
		SLOT_LEGS: Color(0.42, 0.38, 0.40),
		SLOT_FEET: Color(0.44, 0.36, 0.30),
		"accent": Color(0.70, 0.66, 0.60),
	},
	{
		SLOT_TORSO: Color(0.34, 0.36, 0.44),
		SLOT_LEGS: Color(0.30, 0.30, 0.34),
		SLOT_FEET: Color(0.36, 0.32, 0.30),
		"accent": Color(0.64, 0.62, 0.58),
	},
]

## The sleeves belong to the coat, and the neck and shoulder pieces to the trim, so
## neither is rolled: they follow.
const SLOTS_FOLLOWING_TORSO: Array[StringName] = [SLOT_ARMS]
const SLOTS_FOLLOWING_ACCENT: Array[StringName] = [SLOT_NECK, SLOT_SHOULDERS, SLOT_HEAD]

## Only ever darkens. The base colour map is the lightest the skin should read, and a
## tint above 1.0 blows the shading out of it.
const SKIN_TINTS: Array[Color] = [
	Color(1.00, 1.00, 1.00),
	Color(0.92, 0.86, 0.80),
	Color(0.78, 0.68, 0.60),
	Color(0.62, 0.52, 0.45),
]

## The beard follows the hair, because a man with a black beard and blond hair is a
## disguise rather than a person.
const HAIR_TINTS: Array[Color] = [
	Color(1.00, 1.00, 1.00),
	Color(0.45, 0.34, 0.26),
	Color(0.28, 0.24, 0.22),
	Color(0.72, 0.62, 0.46),
	Color(0.70, 0.70, 0.72),
]

## The seven who are evidence. A named passenger has to be recognisable two carriages
## later, so their clothes are written down rather than rolled, and every piece here is
## one [constant POOL] ships.
##
## [code]palette[/code] takes the same shape as [constant PALETTES]; [code]tints[/code]
## overrides single slots on top of it. Accessories are named by model and checked
## against the outfit that owns them, so nobody can be handed a pauldron off a suit
## they are not wearing.
##
## Anyone not listed rolls off their content id, which is what the crowd does.
const CAST := {
	&"beaumont": {
		"stature_metres": 1.61,
		"body": &"regular_female",
		"outfit": &"female_noble",
		"hair": &"long",
		"accessories": ["models/outfits/Female_Noble_Acc_Gorget.glb"],
		"palette": {
			SLOT_TORSO: Color(0.30, 0.29, 0.32),
			SLOT_LEGS: Color(0.26, 0.25, 0.28),
			SLOT_FEET: Color(0.24, 0.22, 0.22),
			"accent": Color(0.52, 0.50, 0.54),
		},
		"skin_tint": Color(0.96, 0.92, 0.88),
		"hair_tint": Color(0.72, 0.72, 0.74),
	},
	&"carrow": {
		"stature_metres": 1.55,
		"body": &"teen_female",
		"outfit": &"female_peasant",
		"hair": &"bob",
		"palette": {
			SLOT_TORSO: Color(0.58, 0.64, 0.60),
			SLOT_LEGS: Color(0.44, 0.48, 0.46),
			SLOT_FEET: Color(0.40, 0.36, 0.32),
			"accent": Color(0.76, 0.72, 0.62),
		},
		"skin_tint": Color(0.92, 0.86, 0.80),
		"hair_tint": Color(0.45, 0.34, 0.26),
	},
	&"dupont": {
		"stature_metres": 1.71,
		"body": &"regular_male",
		"outfit": &"male_peasant",
		"hair": &"simple_parted",
		"beard": &"beard",
		"palette": {
			SLOT_TORSO: Color(0.85, 0.76, 0.66),
			SLOT_LEGS: Color(0.62, 0.56, 0.48),
			SLOT_FEET: Color(0.50, 0.42, 0.34),
			"accent": Color(0.70, 0.62, 0.46),
		},
		"skin_tint": Color(0.78, 0.68, 0.60),
		"hair_tint": Color(0.28, 0.24, 0.22),
	},
	&"thompson": {
		"stature_metres": 1.84,
		"body": &"regular_male",
		"outfit": &"male_noble",
		"hair": &"simple_parted",
		"palette": {
			SLOT_TORSO: Color(0.60, 0.50, 0.50),
			SLOT_LEGS: Color(0.42, 0.38, 0.40),
			SLOT_FEET: Color(0.44, 0.36, 0.30),
			"accent": Color(0.70, 0.66, 0.60),
		},
		"skin_tint": Color(1.00, 1.00, 1.00),
		"hair_tint": Color(0.72, 0.62, 0.46),
	},
	&"weiss": {
		"stature_metres": 1.69,
		"body": &"regular_male",
		"outfit": &"male_noble",
		"hair": &"simple_parted",
		"beard": &"beard",
		"accessories": ["models/outfits/Male_Noble_Acc_Gorget.glb"],
		"palette": {
			SLOT_TORSO: Color(0.44, 0.46, 0.52),
			SLOT_LEGS: Color(0.34, 0.35, 0.40),
			SLOT_FEET: Color(0.32, 0.29, 0.28),
			"accent": Color(0.80, 0.78, 0.74),
		},
		"skin_tint": Color(0.92, 0.86, 0.80),
		"hair_tint": Color(0.70, 0.70, 0.72),
	},
	## The company's dark blue, worn to the shine at the elbows. The gorget stands in
	## for a uniform collar, which is the only piece in the pack that reads as one.
	&"moreau": {
		"stature_metres": 1.74,
		"body": &"regular_male",
		"outfit": &"male_noble",
		"hair": &"simple_parted",
		"beard": &"beard",
		"accessories": ["models/outfits/Male_Noble_Acc_Gorget.glb"],
		"palette": {
			SLOT_TORSO: Color(0.26, 0.30, 0.44),
			SLOT_LEGS: Color(0.22, 0.25, 0.36),
			SLOT_FEET: Color(0.28, 0.25, 0.24),
			"accent": Color(0.78, 0.70, 0.42),
		},
		"tints": {SLOT_NECK: Color(0.86, 0.76, 0.44)},
		"skin_tint": Color(0.78, 0.68, 0.60),
		"hair_tint": Color(0.70, 0.70, 0.72),
	},
	## Steel left steel, and the cloth under it the grey of a cloak that has been rained
	## on since Calais. The scarf is the Order's colour and the only thing on her that
	## is a colour at all.
	&"marchand": {
		"stature_metres": 1.73,
		"body": &"regular_female",
		"outfit": &"female_knight",
		"hair": &"ponytail",
		"accessories": [
			"models/outfits/Female_Knight_Acc_Scarf.glb",
			"models/outfits/Female_Knight_Acc_Pauldrons_Round.glb",
		],
		"palette": {
			SLOT_TORSO: Color(0.74, 0.74, 0.76),
			SLOT_LEGS: Color(0.56, 0.55, 0.58),
			SLOT_FEET: Color(0.62, 0.62, 0.64),
			"accent": Color(0.80, 0.80, 0.82),
		},
		"tints": {SLOT_NECK: Color(0.62, 0.24, 0.20)},
		"skin_tint": Color(0.92, 0.86, 0.80),
		"hair_tint": Color(0.45, 0.34, 0.26),
	},
}

## Odds an accessory the outfit offers is actually worn, per accessory.
const ACCESSORY_CHANCE := 0.5

## Odds a man who could grow one has.
const BEARD_CHANCE := 0.35


## The path the game loads a catalogued piece from. Always the kit, never the library:
## a rig that reached into res://assets/characters would work in the editor and
## disappear in the Web build.
static func kit_path(relative: String) -> String:
	return "%s/%s" % [KIT_DIR, relative]


static func library_path(relative: String) -> String:
	return "%s/%s" % [LIBRARY_DIR, relative]


## A whole character, decided by [param character_seed] alone. The same seed is the
## same person on every machine and every reload, which is what lets a passenger be
## recognised as the woman in the grey coat two carriages later.
static func roll(character_seed: int, wearing: StringName = &"") -> CAppearance:
	var rng := RandomNumberGenerator.new()
	rng.seed = character_seed

	var appearance := CAppearance.new()
	appearance.character_seed = character_seed
	# A forced suit decides the sex before the body does, because there is no male cut
	# of her armour and no amount of scaling makes one.
	var bodies: Array = POOL["bodies"]
	if OUTFITS.has(wearing):
		bodies = _matching(bodies, BODIES, OUTFITS[wearing]["sex"])
		if STYLES[OUTFITS[wearing]["style"]].get("adult_only", false):
			bodies = bodies.filter(func(key: StringName) -> bool: return BODIES[key]["adult"])
	appearance.body = _pick(rng, bodies)

	var sex: StringName = BODIES[appearance.body]["sex"]
	appearance.hair = _pick(rng, _matching(POOL["hair"], HAIR, sex))

	var beards: Array = _matching(POOL["beards"], BEARDS, sex)
	if not beards.is_empty() and rng.randf() < BEARD_CHANCE:
		appearance.beard = _pick(rng, beards)

	_dress(rng, appearance, sex, wearing)

	for accessory: Dictionary in OUTFITS[appearance.outfit]["accessories"]:
		if rng.randf() >= ACCESSORY_CHANCE:
			continue
		wear(appearance, accessory)

	var stature: Vector2 = BODIES[appearance.body]["stature_metres"]
	appearance.stature_metres = rng.randf_range(stature.x, stature.y)

	paint(appearance, PALETTES[rng.randi() % PALETTES.size()])
	appearance.tints[SLOT_SKIN] = SKIN_TINTS[rng.randi() % SKIN_TINTS.size()]
	appearance.tints[SLOT_HAIR] = HAIR_TINTS[rng.randi() % HAIR_TINTS.size()]
	return appearance


## Fills the four covering slots, one garment at a time, out of whatever suits sit in
## the same group as the coat.
##
## The coat is picked first and the rest follow it, because the torso is what a person
## is read by: everything else is chosen to go with something rather than each piece
## being chosen against nothing.
##
## A [code]whole_set[/code] style skips the mixing entirely and arrives as it was made.
## [param wearing] names a suit to put on rather than roll for, which is how a retinue
## is dressed: sworn orders are kept out of the crowd rolls, and asking for one by name
## is the only way anybody gets into plate.
static func _dress(rng: RandomNumberGenerator, appearance: CAppearance, sex: StringName,
		wearing: StringName = &"") -> void:
	var suits := _rollable(POOL["outfits"], OUTFITS, sex, appearance.body)
	var coat: StringName = wearing if OUTFITS.has(wearing) else _pick(rng, suits)
	appearance.outfit = coat

	var style: Dictionary = STYLES[OUTFITS[coat]["style"]]
	if style.get("whole_set", false):
		appearance.parts = OUTFITS[coat]["parts"].duplicate()
		return

	var mixable := suits.filter(func(key: StringName) -> bool:
		var other: Dictionary = STYLES[OUTFITS[key]["style"]]
		return not other.get("whole_set", false) and other["group"] == style["group"])

	appearance.parts = {SLOT_TORSO: OUTFITS[coat]["parts"][SLOT_TORSO]}
	for slot: StringName in COVERING_SLOTS:
		if slot == SLOT_TORSO:
			continue
		var from: StringName = _pick(rng, mixable)
		appearance.parts[slot] = OUTFITS[from]["parts"][slot]


## Puts one accessory on, and takes off whatever it would be worn through. A helmet
## hides the hair rather than growing it out through the crown, and a second pauldron
## replaces the first rather than sharing a shoulder with it.
##
## The first one in wins the slot, which is what makes a rolled character stable: the
## accessory list is walked in catalogue order, so the same seed makes the same choices
## in the same sequence.
static func wear(appearance: CAppearance, accessory: Dictionary) -> void:
	var slot: StringName = accessory["slot"]
	if appearance.accessories.has(slot):
		return
	appearance.accessories[slot] = accessory["model"]
	for hidden: StringName in accessory.get("hides", []):
		if hidden == SLOT_HAIR:
			appearance.hair = &""
		elif hidden == SLOT_BEARD:
			appearance.beard = &""


## Spreads one palette across everything cloth. The sleeves take the coat's colour and
## the trim takes the accent, so a palette decides a person rather than a garment.
static func paint(appearance: CAppearance, palette: Dictionary) -> void:
	for slot: StringName in [SLOT_TORSO, SLOT_LEGS, SLOT_FEET]:
		appearance.tints[slot] = palette.get(slot, Color.WHITE)
	for slot: StringName in SLOTS_FOLLOWING_TORSO:
		appearance.tints[slot] = palette.get(SLOT_TORSO, Color.WHITE)
	for slot: StringName in SLOTS_FOLLOWING_ACCENT:
		appearance.tints[slot] = palette.get("accent", Color.WHITE)


## A seed for [method roll] from an authored id, so unnamed passengers are stable
## without anyone writing a number into the content.
static func seed_of(content_id: StringName) -> int:
	return int(String(content_id).hash())


## What the passenger with [param content_id] wears: what [constant CAST] says, or a
## roll off their id when nobody has written them down.
static func appearance_of(content_id: StringName) -> CAppearance:
	if not CAST.has(content_id):
		return roll(seed_of(content_id))

	var written: Dictionary = CAST[content_id]
	var appearance := CAppearance.new()
	appearance.character_seed = seed_of(content_id)
	appearance.body = written.get("body", &"regular_male")
	appearance.outfit = written.get("outfit", &"male_peasant")
	appearance.parts = OUTFITS[appearance.outfit]["parts"].duplicate()
	# A written character can swap a single garment without leaving the suit behind,
	# which is how the conductor gets trousers that are not the coat's.
	for slot: StringName in written.get("parts", {}):
		appearance.parts[slot] = written["parts"][slot]
	appearance.hair = written.get("hair", &"")
	appearance.beard = written.get("beard", &"")
	appearance.stature_metres = written.get("stature_metres",
		BODIES[appearance.body]["stature_metres"].y)

	# Named by model, resolved to a slot through the outfit that owns it, so a written
	# character cannot be given a piece from a suit they are not wearing.
	for model: String in written.get("accessories", []):
		var accessory := accessory_of(appearance.outfit, model)
		if accessory.is_empty():
			push_error("Wardrobe: %s wears %s, which %s does not offer"
				% [content_id, model, appearance.outfit])
			continue
		wear(appearance, accessory)

	paint(appearance, written.get("palette", PALETTES[0]))
	appearance.tints[SLOT_SKIN] = written.get("skin_tint", Color.WHITE)
	appearance.tints[SLOT_HAIR] = written.get("hair_tint", Color.WHITE)
	# Written last, so a character who wants one sleeve a different colour can say so
	# without restating the palette.
	for slot: StringName in written.get("tints", {}):
		appearance.tints[slot] = written["tints"][slot]
	return appearance


## The catalogue entry for one of [param outfit]'s accessories, or {} when that outfit
## does not offer it.
static func accessory_of(outfit: StringName, model: String) -> Dictionary:
	if not OUTFITS.has(outfit):
		return {}
	for accessory: Dictionary in OUTFITS[outfit]["accessories"]:
		if accessory["model"] == model:
			return accessory
	return {}


## Every glb the rig grafts onto the body, each with the slot it sits in, in the order
## they go on: hair first, then the outfit, then whatever is worn over it, because a
## pauldron belongs over a sleeve and not under one.
static func pieces_of(appearance: CAppearance) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	if HAIR.has(appearance.hair):
		pieces.append({"model": HAIR[appearance.hair]["model"], "slot": SLOT_HAIR})
	if BEARDS.has(appearance.beard):
		pieces.append({"model": BEARDS[appearance.beard]["model"], "slot": SLOT_BEARD})
	for slot: StringName in COVERING_SLOTS:
		var model: String = appearance.parts.get(slot, "")
		if model == "":
			push_error("Wardrobe: %s is wearing nothing on the %s" % [appearance.outfit, slot])
			continue
		pieces.append({"model": model, "slot": slot})
	for slot: StringName in appearance.accessories:
		pieces.append({"model": appearance.accessories[slot], "slot": slot})
	return pieces


## What [param slot] is dyed on this character. White where nothing says otherwise,
## which leaves the texture as it was authored.
static func tint_of(appearance: CAppearance, slot: StringName) -> Color:
	return appearance.tints.get(slot, Color.WHITE)


static func body_model_of(appearance: CAppearance) -> String:
	return BODIES[appearance.body]["model"] if BODIES.has(appearance.body) else ""


static func skin_material_of(appearance: CAppearance) -> StringName:
	return BODIES[appearance.body]["skin_material"] if BODIES.has(appearance.body) else &""


## Every model the pool can ask for, which is what tools/build_cast_kit.gd copies.
## Library-relative, deduplicated, order not meaningful.
static func pooled_models() -> PackedStringArray:
	var models := PackedStringArray()
	for key: StringName in POOL["bodies"]:
		_append_once(models, BODIES[key]["model"])
	for key: StringName in POOL["hair"]:
		_append_once(models, HAIR[key]["model"])
	for key: StringName in POOL["beards"]:
		_append_once(models, BEARDS[key]["model"])
	for key: StringName in POOL["outfits"]:
		for slot: StringName in OUTFITS[key]["parts"]:
			_append_once(models, OUTFITS[key]["parts"][slot])
		for accessory: Dictionary in OUTFITS[key]["accessories"]:
			_append_once(models, accessory["model"])
	return models


## Catalogue entries from [param keys] that the given sex can wear. Anything marked
## `any` is in both lists.
static func _matching(keys: Array, catalogue: Dictionary, sex: StringName) -> Array:
	return keys.filter(func(key: StringName) -> bool:
		if not catalogue.has(key):
			return false
		var wearer: StringName = catalogue[key]["sex"]
		return wearer == sex or wearer == &"any")


## What [method roll] may choose from: the shipped list, minus anything the catalogue
## keeps out of the crowd, minus anything this body has no business wearing.
static func _rollable(keys: Array, catalogue: Dictionary, sex: StringName,
		body: StringName = &"") -> Array:
	return _matching(keys, catalogue, sex).filter(func(key: StringName) -> bool:
		var style: Dictionary = STYLES[catalogue[key]["style"]]
		if not style.get("crowd", true):
			return false
		if style.get("adult_only", false) and BODIES.has(body) and not BODIES[body]["adult"]:
			return false
		return true)


static func _pick(rng: RandomNumberGenerator, from: Array) -> StringName:
	return from[rng.randi() % from.size()] if not from.is_empty() else &""


static func _append_once(into: PackedStringArray, path: String) -> void:
	if path != "" and into.find(path) < 0:
		into.append(path)
