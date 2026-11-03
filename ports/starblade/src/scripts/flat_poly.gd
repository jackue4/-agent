extends Node2D
## Polygon2D stand-in for per-frame HUD animation on Web/Compatibility.
## Colour goes through self_modulate (no geometry rebuild) and the shape is only
## re-submitted when it actually changes, avoiding the WebGL2 index-buffer errors
## and per-frame buffer churn caused by re-setting Polygon2D.polygon every frame.

var polygon := PackedVector2Array():
	set(v):
		if v == polygon: return
		polygon = v; queue_redraw()
var color := Color.WHITE:
	set(v):
		color = v; self_modulate = v

func _draw() -> void:
	if polygon.size() >= 3: draw_colored_polygon(polygon,Color.WHITE)
