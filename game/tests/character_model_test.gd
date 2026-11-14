extends GdUnitTestSuite
## The humanoid model animates in place: no clip moves its root sideways, so the model never
## walks away from its body and snaps back when the clip ends (the M13 play-test's "teleport
## back after combos").


func test_clips_keep_the_root_in_place() -> void:
	var model := auto_free(CharacterModel.new(CharacterModel.HUMAN, {})) as CharacterModel
	var player := model.animation
	for clip_name in player.get_animation_list():
		var clip := player.get_animation(clip_name)
		for track in clip.get_track_count():
			var path := String(clip.track_get_path(track))
			if (
				clip.track_get_type(track) != Animation.TYPE_POSITION_3D
				or not path.ends_with(":Root")
			):
				continue
			var first := clip.position_track_interpolate(track, 0.0)
			for i in 21:
				var at := clip.position_track_interpolate(track, clip.length * i / 20.0)
				var sideways := Vector2(at.x - first.x, at.z - first.z).length()
				(
					assert_float(sideways)
					. override_failure_message("%s moves its root %.2f m" % [clip_name, sideways])
					. is_less(0.05)
				)


## PlayerView.ROLL_CLIP_TRAVEL: the roll's root motion twin stops moving there, so the feet of
## the in-place Roll clip are planted from then on.
func test_roll_clip_plants_its_feet_at_roll_clip_travel() -> void:
	var scene := auto_free((load(CharacterModel.HUMAN) as PackedScene).instantiate()) as Node
	var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var clip := player.get_animation(&"Roll_RM")
	var root := -1
	for track in clip.get_track_count():
		var path := String(clip.track_get_path(track))
		if path.ends_with(":Root") and clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
			root = track
	assert_int(root).is_greater_equal(0)
	var at := PlayerView.ROLL_CLIP_TRAVEL * clip.length
	var planted: Vector3 = clip.position_track_interpolate(root, at)
	var before: Vector3 = clip.position_track_interpolate(root, at - 0.1 * clip.length)
	var end: Vector3 = clip.position_track_interpolate(root, clip.length)
	assert_float(planted.distance_to(end)).is_less(0.05)
	assert_float(before.distance_to(end)).is_greater(0.5)
