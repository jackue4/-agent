extends Node
## Executes once in the actual immutable Web game. No native-input mirroring.

var _ugc: Node
var _manifest: Dictionary = {}
var _session := ""
var _busy := false
var _command: Dictionary = {}
var _seen: Dictionary = {}
var _last_draw_us := 0
var _frame_count := 0
var _elapsed_ms := 0.0
var _max_frame_ms := 0.0
var _jank_frames := 0
var _samples: Array[float] = []

func configure(ugc: Node, manifest: Dictionary, session_id: String) -> void:
	_ugc = ugc
	_manifest = manifest.duplicate()
	_session = session_id
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.frame_post_draw.connect(_drawn)

func _drawn() -> void:
	var now := Time.get_ticks_usec()
	if _busy and _last_draw_us > 0:
		var ms := float(now - _last_draw_us) / 1000.0
		_frame_count += 1
		_elapsed_ms += ms
		_max_frame_ms = maxf(_max_frame_ms, ms)
		if ms > 33.34:
			_jank_frames += 1
		_samples.append(ms)
		if _samples.size() > 600:
			_samples.pop_front()
	_last_draw_us = now

func _metrics() -> Dictionary:
	var ordered := _samples.duplicate()
	ordered.sort()
	return {"frames": _frame_count, "sampleMs": _elapsed_ms, "fps": float(_frame_count) * 1000.0 / _elapsed_ms if _elapsed_ms > 0 else 0.0, "maxFrameMs": _max_frame_ms, "jankFrames": _jank_frames, "p95FrameMs": ordered[mini(ordered.size() - 1, int(ordered.size() * 0.95))] if not ordered.is_empty() else 0.0}

func submit(command: Dictionary) -> void:
	if str(command.get("runtimeSession", "")) != _session or str(command.get("buildId", "")) != str(_manifest.get("buildId", "")) or str(command.get("sourceRevision", "")) != str(_manifest.get("sourceRevision", "")):
		return
	if command.get("kind") == "stop":
		_busy = false
		get_tree().paused = true
		return
	if _busy or str(command.get("commandId", "")) == "" or _seen.has(command.get("commandId")):
		return
	if str(command.get("kind", "")) not in ["run", "eval", "test"]:
		return
	_seen[command.commandId] = true
	_command = command.duplicate(true)
	_busy = true
	_frame_count = 0
	_elapsed_ms = 0.0
	_max_frame_ms = 0.0
	_jank_frames = 0
	_last_draw_us = 0
	_samples.clear()
	_ugc.checks.clear()
	_execute.call_deferred()
	_progress.call_deferred(str(command.commandId))

func _envelope(message_type: String, data: Dictionary) -> Dictionary:
	var out := {"type": message_type, "data": data}
	for key in ["clientId", "commandId", "runtimeSession", "buildId", "sourceRevision", "kind", "runId"]:
		out[key] = _command.get(key, "")
	return out

func _progress(command_id: String) -> void:
	while _busy and str(_command.get("commandId")) == command_id:
		_ugc.emit(_envelope("runtime_test_progress", {"checks": _ugc.checks.duplicate(true), "metrics": _metrics(), "state": _ugc._state()}))
		await get_tree().create_timer(0.25, true, false, true).timeout

func _image() -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var image: Image = await _ugc._grab()
	if image == null or image.is_empty():
		return ""
	var ratio := 960.0 / maxf(image.get_width(), image.get_height())
	if ratio < 1.0:
		image.resize(maxi(1, int(image.get_width() * ratio)), maxi(1, int(image.get_height() * ratio)), Image.INTERPOLATE_BILINEAR)
	return Marshalls.raw_to_base64(image.save_jpg_to_buffer(0.72))

func _execute() -> void:
	var payload: Dictionary = _command.get("payload", {})
	var game: Node = _ugc.game()
	var result := {"loaded": game != null, "ok": game != null, "errors": [], "checks": [], "has_test": false, "image": "", "image_end": ""}
	if game == null:
		result.errors.append({"file": "main", "message": "当前浏览器场景没有载入", "kind": "error"})
	elif _command.kind == "eval":
		var evaluated: Dictionary = await _ugc.eval_code(str(payload.get("code", "")), clampi(int(payload.get("timeoutMs", 15000)), 100, 45000))
		result.merge(evaluated, true)
		var settle := clampf(float(payload.get("settle", 0.3)), 0.0, 5.0)
		if settle > 0:
			await get_tree().create_timer(settle, true, false, true).timeout
	elif _command.kind == "test":
		result.has_test = game.has_method("auto_test")
		if result.has_test:
			if bool(payload.get("shot", true)):
				result.image = await _image()
			await game.call("auto_test")
		else:
			result.errors.append({"file": "main", "message": "主场景缺少 auto_test()", "kind": "error"})
	if bool(payload.get("shot", true)):
		if _command.kind == "test":
			result.image_end = await _image()
		else:
			result.image = await _image()
	result.errors.append_array(_ugc.take_errors())
	result.checks = _ugc.checks.duplicate(true)
	result.state = _ugc._state()
	result.result = _ugc.result
	result.score = _ugc.score
	result.metrics = _metrics()
	for error in result.errors:
		if error.get("kind", "error") != "warning":
			result.ok = false
	if _command.kind == "test":
		result.ok = result.ok and result.has_test and not result.checks.is_empty()
		for check in result.checks:
			result.ok = result.ok and bool(check.get("ok", false))
	_ugc.emit(_envelope("runtime_test_result", result))
	_busy = false
