extends Node
## Runtime asset cache: textures, glTF models and audio streamed from the platform server.
signal changed(id: String)

var items := {}  # id -> {state, kind, url, res}

func state(id: String) -> String:
	if not items.has(id):
		return "none"
	return items[id].state

func get_res(id: String):
	if items.has(id) and items[id].state == "ready":
		return items[id].res
	return null

func register(id: String, kind: String, st: String, url: String) -> void:
	if id == "":
		return
	var cur = items.get(id, {})
	if st == "ready" and url != "":
		if cur.get("url", "") == url and (cur.get("state") == "ready" or cur.get("state") == "loading"):
			return
		items[id] = {"state": "loading", "kind": kind, "url": url, "res": null}
		changed.emit(id)
		_fetch(id, kind, url)
	elif st == "failed":
		items[id] = {"state": "failed", "kind": kind, "url": url, "res": null}
		changed.emit(id)
	else:
		if cur.get("state", "") == "ready":
			return
		items[id] = {"state": "pending", "kind": kind, "url": "", "res": null}
		changed.emit(id)

func register_all(dict) -> void:
	if typeof(dict) != TYPE_DICTIONARY:
		return
	for id in dict:
		var a = dict[id]
		if typeof(a) == TYPE_DICTIONARY:
			register(str(id), str(a.get("kind", "sprite")), str(a.get("state", "pending")), str(a.get("url", "")))

func _fetch(id: String, kind: String, url: String) -> void:
	var req := HTTPRequest.new()
	req.body_size_limit = 64 * 1024 * 1024
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body): _on_done(req, id, kind, url, result, code, body))
	var err := req.request(url)
	if err != OK:
		req.queue_free()
		items[id] = {"state": "failed", "kind": kind, "url": url, "res": null}
		changed.emit(id)

func _on_done(req: HTTPRequest, id: String, kind: String, url: String, result: int, code: int, body: PackedByteArray) -> void:
	req.queue_free()
	if items.get(id, {}).get("url", "") != url:
		return
	var res = null
	if result == HTTPRequest.RESULT_SUCCESS and code < 400 and body.size() > 0:
		match kind:
			"sprite", "background", "texture":
				res = _make_texture(body, kind)
			"model3d":
				res = _make_model(body)
			"music", "sfx":
				res = _make_audio(body, kind)
	if res == null:
		items[id] = {"state": "failed", "kind": kind, "url": url, "res": null}
	else:
		items[id] = {"state": "ready", "kind": kind, "url": url, "res": res}
	changed.emit(id)

func _make_texture(body: PackedByteArray, kind: String):
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if body.size() > 4 and body[0] == 0x89 and body[1] == 0x50:
		err = img.load_png_from_buffer(body)
	elif body.size() > 3 and body[0] == 0xFF and body[1] == 0xD8:
		err = img.load_jpg_from_buffer(body)
	elif body.size() > 12 and body[0] == 0x52 and body[8] == 0x57:
		err = img.load_webp_from_buffer(body)
	else:
		err = img.load_png_from_buffer(body)
		if err != OK:
			err = img.load_jpg_from_buffer(body)
	if err != OK:
		return null
	if img.is_compressed():
		img.decompress()
	if kind == "sprite":
		img.convert(Image.FORMAT_RGBA8)
		var used := img.get_used_rect()
		if used.size.x > 4 and used.size.y > 4:
			img = img.get_region(used)
		var m := maxf(img.get_width(), img.get_height())
		if m > 384.0:
			var k := 384.0 / m
			img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	elif kind == "texture":
		var m2 := maxf(img.get_width(), img.get_height())
		if m2 > 256.0:
			var k2 := 256.0 / m2
			img.resize(maxi(1, int(img.get_width() * k2)), maxi(1, int(img.get_height() * k2)), Image.INTERPOLATE_LANCZOS)
	else:
		var m3 := maxf(img.get_width(), img.get_height())
		if m3 > 1600.0:
			var k3 := 1600.0 / m3
			img.resize(int(img.get_width() * k3), int(img.get_height() * k3), Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make_model(body: PackedByteArray):
	# glTF binary starts with "glTF"; anything else is treated as FBX (Hunyuan 3D output).
	var is_glb := body.size() > 4 and body[0] == 0x67 and body[1] == 0x6C and body[2] == 0x54 and body[3] == 0x46
	var doc: GLTFDocument = GLTFDocument.new() if is_glb else FBXDocument.new()
	var st: GLTFState = GLTFState.new() if is_glb else FBXState.new()
	var err := doc.append_from_buffer(body, "", st)
	if err != OK and not is_glb:
		doc = GLTFDocument.new()
		st = GLTFState.new()
		err = doc.append_from_buffer(body, "", st)
	if err != OK:
		push_warning("model decode failed: %d" % err)
		return null
	var scene := doc.generate_scene(st)
	if scene == null:
		return null
	return scene

func _make_audio(body: PackedByteArray, kind: String):
	var s = null
	if body.size() > 4 and body[0] == 0x4F and body[1] == 0x67:
		s = AudioStreamOggVorbis.load_from_buffer(body)
	elif body.size() > 4 and body[0] == 0x52 and body[1] == 0x49:
		s = AudioStreamWAV.load_from_buffer(body)
	else:
		var mp := AudioStreamMP3.new()
		mp.data = body
		s = mp
	if s != null and kind == "music":
		if s is AudioStreamMP3:
			s.loop = true
		elif s is AudioStreamOggVorbis:
			s.loop = true
	return s

## Instance a model asset scaled to fit inside the given box size.
func instance_model(id: String, fit: Vector3) -> Node3D:
	var src = get_res(id)
	if src == null:
		return null
	var inst: Node3D = src.duplicate()
	# holder (entity space) -> pivot (fit scale/offset) -> inst (keeps its own import transform, e.g. FBX unit scale)
	var holder := Node3D.new()
	var pivot := Node3D.new()
	holder.add_child(pivot)
	pivot.add_child(inst)
	var aabb := _calc_aabb(inst, Transform3D.IDENTITY)
	if aabb.size.length() > 0.0001:
		var k := minf(fit.x / maxf(aabb.size.x, 0.001), minf(fit.y / maxf(aabb.size.y, 0.001), fit.z / maxf(aabb.size.z, 0.001)))
		pivot.scale = Vector3.ONE * k
		var c := aabb.get_center()
		pivot.position = Vector3(-c.x * k, -aabb.position.y * k - fit.y * 0.5, -c.z * k)
	return holder

func _calc_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var a := _calc_aabb(c, t)
		if a.size.length() > 0.0:
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
	return out
