class_name ItemDef
extends Resource
## One kind of item (M23). Files live in res://data/items/, the id is the file name; Items.ids
## numbers them for the rolled back state.

enum Kind { WEAPON, SHIELD, RANGED, ARMOR, TRINKET, MATERIAL, BOLT, CONSUMABLE }
## The gear slot an item goes to (NONE: bag only).
enum Slot { NONE, MAIN, OFF, RANGED, HELM, CHEST, LEGS, CAPE, TRINKET, BOLTS }

@export var id: StringName = &""
@export var title := ""
@export var kind := Kind.MATERIAL
@export var slot := Slot.NONE
## Most items in one stack.
@export var stack := 1
## 0 common (white), 1 green, 2 blue, 3 purple, 4 gold.
@export_range(0, 4) var rarity := 0
@export var weight := 0.1
## Weapons and crossbows: multiplier on the attack's damage (1.0 is the starting kit).
@export var damage := 1.0
## Armor: flat damage removed from each hit. Shield: extra share of a hit a block stops.
@export var defense := 0.0
@export var stamina := 0.0
## Consumables: health restored.
@export var heal := 0.0
@export var icon: Texture2D
## A prop glTF (res://assets/...) for its look in the hand or on the ground.
@export var model := ""
## The CharacterModel.show_prop name of a hand item.
@export var prop: StringName = &""
