class_name Stick
extends RefCounted
## Draws a procedural stick-figure fighter from a pose dictionary (joint positions, facing right).


static func pt(pose: Dictionary, k: String, facing: float, off: Vector2) -> Vector2:
	var v: Vector2 = pose[k]
	return Vector2(v.x * facing, v.y) + off


static func draw(ci: CanvasItem, pose: Dictionary, facing: float, off: Vector2, ink: Color, back: Color, head_fill: Color, w: float, band: Color) -> void:
	var hip := pt(pose, "hip", facing, off)
	var neck := pt(pose, "neck", facing, off)
	var head := pt(pose, "head", facing, off)
	var sh := neck + Vector2(0, 5)
	# back limbs
	Ink.limb(ci, sh, pt(pose, "eL", facing, off), pt(pose, "hL", facing, off), back, w * 0.9)
	Ink.limb(ci, hip, pt(pose, "kL", facing, off), pt(pose, "fL", facing, off), back, w * 0.9)
	ci.draw_circle(pt(pose, "hL", facing, off), w * 0.8, back, true, -1.0, false)
	# torso
	ci.draw_line(hip, neck, ink, w * 1.2)
	ci.draw_circle(hip, w * 0.6, ink, true, -1.0, false)
	ci.draw_circle(neck, w * 0.6, ink, true, -1.0, false)
	# front limbs
	Ink.limb(ci, hip, pt(pose, "kR", facing, off), pt(pose, "fR", facing, off), ink, w)
	Ink.limb(ci, sh, pt(pose, "eR", facing, off), pt(pose, "hR", facing, off), ink, w)
	ci.draw_circle(pt(pose, "hR", facing, off), w * 0.9, ink, true, -1.0, false)
	# head
	Ink.circle(ci, head, 13.0, head_fill, 4.5, ink)
	if band.a > 0.0:
		ci.draw_line(head + Vector2(-12.0 * facing, -4), head + Vector2(12.5 * facing, -6), band, 5.0)
	ci.draw_circle(head + Vector2(5.5 * facing, -0.5), 2.8, ink, true, -1.0, false)
	ci.draw_line(head + Vector2(1.0 * facing, -4.5), head + Vector2(10.0 * facing, -1.5), ink, 3.0)
	ci.draw_line(head + Vector2(3.0 * facing, 6.0), head + Vector2(9.0 * facing, 5.0), ink, 2.0)
