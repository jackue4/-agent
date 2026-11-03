extends Control
## Generated illustration, rarity frame and restrained card interaction.
signal activated
signal reveal_finished
signal landed
const FOIL_SHADER := preload("res://assets/card_foil.gdshader")
const THEMES := ["zeus","poseidon","athena","aphrodite","artemis","ares","dionysus","demeter","hammer","duo"]
const PERK_THEMES := {"chain":"zeus","frost":"demeter","power":"ares","penetrate":"ares","haste":"artemis","dash":"artemis","shield":"athena","repair":"aphrodite","leech":"aphrodite","extra":"duo","magnet":"poseidon","range":"poseidon","crit":"artemis","burst":"ares","pierce":"artemis","ricochet":"zeus","recall_cut":"poseidon","quickdraw":"athena","bloom":"dionysus","salvo":"duo"}
static var textures: Dictionary = {}
var theme_key := "duo"
var tint := Color("73eceb")
var reduced_motion := false
var rarity := 0
var image_node: TextureRect
var has_illustration := false
var hovered := false
var hover := 0.0
var clock := 0.0
var press := 0.0
var _origin := Vector2.ZERO
var _held := false
var _press_tween: Tween
var drop_y := 0.0
var landing_squash := 0.0
var landing_flash := 0.0
var revealed := true
var selectable := true
var _surface_texture: Texture2D
var _foil: ShaderMaterial

class IllustrationShade extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_polygon(PackedVector2Array([Vector2(0,h*.58),Vector2(w,h*.58),Vector2(w,h),Vector2(0,h)]),PackedColorArray([Color(0,0,0,0),Color(0,0,0,0),Color(.015,.025,.045,.96),Color(.015,.025,.045,.96)]))
		draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(w,0),Vector2(w,67),Vector2(0,67)]),PackedColorArray([Color(0,0,0,.45),Color(0,0,0,.45),Color(0,0,0,0),Color(0,0,0,0)]))

static func theme_for(entry: Dictionary) -> String:
	var type := str(entry.get("type",""))
	if type == "hammer": return "hammer"
	if type == "duo": return "duo"
	var god := str(entry.get("god","")).to_lower()
	if god in THEMES: return god
	return str(PERK_THEMES.get(str(entry.get("id","")),"duo"))

func configure(entry: Dictionary,reduced: bool = false) -> void:
	theme_key = theme_for(entry)
	tint = Color.from_string(str(entry.get("color","73eceb")),Color("73eceb")) if not entry.get("color") is Color else entry.color
	rarity = int(entry.get("rarity",0)) if str(entry.get("rarity",0)).is_valid_int() else 0
	reduced_motion = reduced
	if is_inside_tree(): _load_illustration()

func _ready() -> void:
	_origin = position
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): hovered = true)
	mouse_exited.connect(func(): hovered = false)
	image_node = TextureRect.new()
	image_node.position = Vector2(20,20)
	image_node.size = Vector2(size.x-40,232)
	image_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(image_node)
	var shade := IllustrationShade.new()
	shade.position = image_node.position
	shade.size = image_node.size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var foil := ColorRect.new()
	foil.size = size
	foil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foil = ShaderMaterial.new()
	_foil.shader = FOIL_SHADER
	_foil.set_shader_parameter("card_size",size)
	_foil.set_shader_parameter("strength",1.0 if rarity >= 3 else (.70 if rarity >= 2 else (.16 if rarity == 1 else 0.0)))
	foil.material = _foil
	add_child(foil)
	_surface_texture = _texture("res://assets/cards/gilded_surface.png")
	_load_illustration()

static func _texture(path: String) -> Texture2D:
	var texture: Texture2D = textures.get(path)
	if texture == null:
		if ResourceLoader.exists(path): texture = load(path) as Texture2D
		if texture != null: textures[path] = texture
	return texture

func _load_illustration() -> void:
	if image_node == null: return
	var texture := _texture("res://assets/cards/"+theme_key+".jpg")
	image_node.texture = texture
	has_illustration = texture != null
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not revealed or not selectable: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_held = true
			press_feedback()
		else:
			if _held and Rect2(Vector2.ZERO,size).has_point(event.position): activated.emit()
			_held = false
		accept_event()

func press_feedback() -> void:
	press = 1.0
	if _press_tween != null and _press_tween.is_valid(): _press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(self,"press",0.0,.16)

func start_reveal(delay: float) -> void:
	if reduced_motion:
		revealed = true
		return
	revealed = false
	drop_y = -1100.0
	position = _origin+Vector2(0,drop_y)
	pivot_offset = Vector2(size.x*.5,size.y)
	visible = false
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func(): visible = true)
	tween.tween_property(self,"drop_y",0.0,.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		landing_squash = 1.0
		landing_flash = 1.0
		landed.emit()
	)
	tween.tween_property(self,"landing_squash",-.22,.065).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self,"landing_squash",0.0,.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		revealed = true
		reveal_finished.emit()
	)

func _process(delta: float) -> void:
	var target := 1.0 if hovered and revealed else 0.0
	hover = move_toward(hover,target,delta*8)
	landing_flash = maxf(0.0,landing_flash-delta*5.0)
	if not reduced_motion:
		clock += delta
		position = _origin+Vector2(0,drop_y-8*hover)
		scale = Vector2(1.0+landing_squash*.035,1.0-landing_squash*.065)*(1.0-press*.012)
	else:
		position = _origin
		scale = Vector2.ONE
	if _foil != null:
		_foil.set_shader_parameter("clock",clock)
		_foil.set_shader_parameter("landing",0.0 if reduced_motion else landing_flash)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO,size)
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0,0,0,.36)
	shadow.set_corner_radius_all(8)
	draw_style_box(shadow,Rect2(Vector2(-2,6+hover*3),size+Vector2(4,4)))
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color("101927").lerp(Color("1c2939"),hover*.45)
	surface.border_color = tint.darkened(.35-hover*.25)
	surface.set_border_width_all(2 if rarity >= 2 else 1)
	surface.set_corner_radius_all(7)
	draw_style_box(surface,rect)
	if _surface_texture != null:
		draw_texture_rect(_surface_texture,rect.grow(-3),false,Color(1,1,1,.94 if rarity >= 2 else .58))
	# Fine engraved grain and double bevel keep even ordinary cards tactile.
	for i in range(252,int(size.y)-12,4):
		draw_line(Vector2(14,i),Vector2(size.x-14,i),Color(.7,.8,.9,.016),1)
	var metal := Color("d7ae66") if rarity >= 2 else tint.darkened(.3)
	draw_rect(rect.grow(-6),Color(metal,.46),false,1)
	for corner in [Vector2(9,9),Vector2(size.x-9,9),Vector2(9,size.y-9),size-Vector2(9,9)]:
		var inward := Vector2(1 if corner.x < size.x*.5 else -1,1 if corner.y < size.y*.5 else -1)
		draw_line(corner,corner+Vector2(inward.x*22,0),metal,2,true)
		draw_line(corner,corner+Vector2(0,inward.y*22),metal,2,true)
	if landing_flash > 0:
		var spread := (1.0-landing_flash)*26.0
		for side in [-1.0,1.0]:
			var origin := Vector2(size.x*.5+side*(size.x*.25+spread),size.y-5)
			draw_line(origin,origin+Vector2(side*45,0),Color(metal,landing_flash*.85),2,true)
	draw_line(Vector2(14,4),Vector2(size.x-14,4),Color(tint,.65+hover*.3),2,true)
	if not has_illustration:
		var art := Rect2(Vector2(12,12),Vector2(size.x-24,236))
		draw_rect(art,tint.darkened(.88))
		for i in range(5):
			var at := Vector2(38+i*58,55+i%2*44)
			draw_line(at,at+Vector2(87,112),Color(tint,.13),16,true)
		draw_arc(Vector2(size.x*.5,130),58,-2.2,2.8,48,Color(tint,.5),2,true)
	if not reduced_motion and rarity >= 1:
		var y := fposmod(clock*38+rarity*77,size.y)
		draw_line(Vector2(2,maxf(4,y-32)),Vector2(2,y),Color(1,1,1,.36),2,true)
		draw_line(Vector2(size.x-2,size.y-y),Vector2(size.x-2,minf(size.y-4,size.y-y+32)),Color(tint,.6),2,true)
	if press > 0:
		draw_rect(rect,Color(tint,press*.13))
