extends RefCounted
## Procedural mesh builders for the 3D runtime: rounded "pillow" slabs built from stacked
## rounded-rectangle rings (platforms, ground, floating-island rocks) and faceted gems.
## Godot treats clockwise triangles as front faces; _tri() orients every triangle against
## its intended normal so builders never have to reason about winding.

const CORNER_SEGS := 4
## Wavelength (metres) of the scalloped "drip" edge on grass/snow caps.
const DRIP_PERIOD := 0.9
const UV_SCALE := 0.25
const ORDER_CW: Array[int] = [0, 1, 2]
const ORDER_CCW: Array[int] = [0, 2, 1]

## Rounded rectangle in the XZ plane: [points, outward normals], corners CCW from +X.
static func outline(ex: float, ez: float, r: float, segs: int) -> Array:
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	r = clampf(r, 0.0, minf(ex, ez))
	var cx := ex - r
	var cz := ez - r
	var centers: Array[Vector2] = [Vector2(cx, cz), Vector2(-cx, cz), Vector2(-cx, -cz), Vector2(cx, -cz)]
	for c in 4:
		for j in segs + 1:
			var a := (c + float(j) / segs) * PI * 0.5
			var d := Vector2(cos(a), sin(a))
			pts.append(centers[c] + d * r)
			nrm.append(d)
	return [pts, nrm]

## A ring description used by slab(): half extents, corner radius, height, vertex colour,
## profile normal (radial, up) and optional scalloped drip / rocky wobble.
static func ring(ex: float, ez: float, r: float, y: float, col: Color, pn: Vector2, drip := 0.0, wobble := 0.0) -> Dictionary:
	return {"ex": maxf(ex, 0.02), "ez": maxf(ez, 0.02), "r": r, "y": y, "col": col, "pn": pn.normalized(), "drip": drip, "wobble": wobble}

static func _ring_verts(rg: Dictionary, segs: int) -> Array:
	var o := outline(rg.ex, rg.ez, rg.r, segs)
	var pts: PackedVector2Array = o[0]
	var nrm: PackedVector2Array = o[1]
	var total := 0.0
	for i in pts.size():
		total += pts[i].distance_to(pts[(i + 1) % pts.size()])
	# Whole number of scallops so the seam is invisible.
	var freq := TAU * maxf(1.0, roundf(total / DRIP_PERIOD)) / maxf(total, 0.001)
	var pn: Vector2 = rg.pn
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var arc := 0.0
	for i in pts.size():
		if i > 0:
			arc += pts[i].distance_to(pts[i - 1])
		var p: Vector2 = pts[i] + nrm[i] * rg.wobble * sin(i * 2.39 + rg.y * 3.1)
		var y: float = rg.y
		if rg.drip > 0.0:
			y -= rg.drip * pow(0.5 + 0.5 * sin(arc * freq), 3.0)
		pos.append(Vector3(p.x, y, p.y))
		nor.append(Vector3(nrm[i].x * pn.x, pn.y, nrm[i].y * pn.x).normalized())
	return [pos, nor]

## Append side strips between consecutive rings (+ optional top/bottom caps) to st.
static func slab(st: SurfaceTool, rings: Array, cap_top: bool, cap_bottom: bool, segs := CORNER_SEGS) -> void:
	var verts: Array = []
	for rg in rings:
		verts.append(_ring_verts(rg, segs))
	for k in rings.size() - 1:
		var a: Array = verts[k]
		var b: Array = verts[k + 1]
		var ca: Color = rings[k].col
		var cb: Color = rings[k + 1].col
		var n: int = a[0].size()
		for i in n:
			var j := (i + 1) % n
			_tri(st, [a[0][i], a[0][j], b[0][j]], [a[1][i], a[1][j], b[1][j]], [ca, ca, cb])
			_tri(st, [a[0][i], b[0][j], b[0][i]], [a[1][i], b[1][j], b[1][i]], [ca, cb, cb])
	if cap_top:
		_cap(st, verts[0], rings[0].col, Vector3.UP)
	if cap_bottom:
		_cap(st, verts[verts.size() - 1], rings[rings.size() - 1].col, Vector3.DOWN)

static func _cap(st: SurfaceTool, v: Array, col: Color, n: Vector3) -> void:
	var pts: PackedVector3Array = v[0]
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	for i in pts.size():
		var j := (i + 1) % pts.size()
		_tri(st, [c, pts[i], pts[j]], [n, n, n], [col, col, col])

## Add one triangle oriented so its front face points along the summed vertex normals.
static func _tri(st: SurfaceTool, p: Array, n: Array, c: Array) -> void:
	var face: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	if face.length_squared() < 1e-12:
		return
	var want: Vector3 = n[0] + n[1] + n[2]
	var order := ORDER_CW if face.dot(want) < 0.0 else ORDER_CCW
	for i in order:
		var v: Vector3 = p[i]
		st.set_color(c[i])
		st.set_normal(n[i])
		st.set_uv(Vector2(v.x, v.z) * UV_SCALE)
		st.add_vertex(v)

## Faceted gem (table, crown, girdle, pavilion) with flat normals, fitting the given size.
static func gem(size: Vector3, sides := 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var top := Vector3(0, size.y * 0.5, 0)
	var tip := Vector3(0, -size.y * 0.5, 0)
	var table: Array[Vector3] = []
	var girdle: Array[Vector3] = []
	for i in sides:
		var a := TAU * i / sides
		var a2 := a + PI / sides
		table.append(Vector3(cos(a2) * hx * 0.55, size.y * 0.5, sin(a2) * hz * 0.55))
		girdle.append(Vector3(cos(a) * hx, size.y * 0.15, sin(a) * hz))
	for i in sides:
		var j := (i + 1) % sides
		_flat(st, [top, table[i], table[j]])
		_flat(st, [table[i], girdle[i], girdle[j]])
		_flat(st, [table[i], girdle[j], table[j]])
		_flat(st, [girdle[i], tip, girdle[j]])
	return st.commit()

## Puffy five-point star prism facing +Z, fitting the given size.
static func star(size: Vector3, points := 5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var depth := size.z * 0.5
	var front := Vector3(0, 0, depth)
	var back := Vector3(0, 0, -depth)
	var ring: Array[Vector3] = []
	for i in points * 2:
		var a := PI * 0.5 + PI * i / points
		var r := 0.5 if i % 2 == 0 else 0.24
		ring.append(Vector3(cos(a) * size.x * r, sin(a) * size.y * r, 0))
	for i in ring.size():
		var j := (i + 1) % ring.size()
		_flat(st, [front, ring[i], ring[j]])
		_flat(st, [back, ring[j], ring[i]])
	return st.commit()

static func _flat(st: SurfaceTool, p: Array) -> void:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	var centroid: Vector3 = (p[0] + p[1] + p[2]) / 3.0
	if n.dot(centroid) < 0.0:
		n = -n
	_tri(st, p, [n, n, n], [Color.WHITE, Color.WHITE, Color.WHITE])