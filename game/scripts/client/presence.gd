class_name Presence
extends Node
## Discord Rich Presence (PLAN §6 M13): the mode (in the menu, Solo, Hosting, In a party), where
## the player is (the keep, the Barrows, facing the Warden), the party size out of
## GameServer.MAX_PLAYERS and the time since the game started. Never the room code. Talks to
## the Discord client through DiscordRichPresence (addons/discord_rich_presence, MIT), which does
## nothing when Discord isn't running, and on Linux and macOS when no netcat is installed.

## The "Stellamortis" application on the Discord developer portal.
const APP_ID := "1563509032348557382"
## The art asset key the logo is uploaded under (Rich Presence > Art Assets).
const LOGO := "logo"
## Seconds between looks at the game state.
const EVERY := 2.0

var _discord: DiscordRichPresence
var _last := {}
var _wait := 0.0
## Unix time the current game started, 0 in the menu.
var _started := 0
## A random id for this game's party, so Discord shows the size; not the room code.
var _party := ""


func _ready() -> void:
	_discord = DiscordRichPresence.new()
	_discord.app_id = APP_ID
	add_child(_discord)


## Shows the menu, or the game client's mode, place and party. Call it every frame; it looks at
## the state every EVERY seconds and only sends changes.
func follow(client: GameClient, delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = EVERY
	var activity := describe(client)
	if client == null:
		_started = 0
	elif _started == 0:
		_started = int(Time.get_unix_time_from_system())
		_party = "stellamortis-%d" % randi()
	if client != null:
		activity["timestamps"] = {"start": _started}
		if client.mode != "solo":
			activity["party"] = {
				"id": _party, "size": [client.player_count(), GameServer.MAX_PLAYERS]
			}
	if activity != _last:
		_last = activity
		_discord.set_activity(activity)


## What Discord shows for this client (null: the menu), without time and party.
static func describe(client: GameClient) -> Dictionary:
	var activity := {"assets": {"large_image": LOGO, "large_text": "Stellamortis"}}
	if client == null:
		activity["details"] = "In the menu"
		return activity
	match client.mode:
		"solo":
			activity["details"] = "Solo"
		"host":
			activity["details"] = "Hosting"
		_:
			activity["details"] = "In a party"
	activity["state"] = place(client)
	return activity


static func place(client: GameClient) -> String:
	if client.me == null:
		return "Arriving"
	var where := Layout.place_at(client.me.global_position)
	if where == Layout.HUB_PLACE:
		return "In the keep"
	if where != Layout.ORIGIN_PLACE:
		return "In the " + String(where).capitalize()
	if Encounter.won(client.me):
		return "The Warden has fallen"
	var fight := client.get_tree().get_first_node_in_group(Encounter.GROUP) as Encounter
	if fight and fight.phase == Encounter.Phase.BOSS:
		return "Facing the Warden"
	return "In the Barrows"
