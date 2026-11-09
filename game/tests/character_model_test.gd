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
