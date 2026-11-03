shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec3 mist_color : source_color = vec3(.6,.72,.84);
varying vec2 world_uv;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() { world_uv=(MODEL_MATRIX*vec4(VERTEX,1)).xz; }
void fragment() {
	vec2 p=world_uv*.035+vec2(TIME*.003,TIME*.001);
	float n=noise(p)*.57+noise(p*2.1)*.28+noise(p*4.3)*.15;
	ALBEDO=mix(mist_color*.65,mist_color*1.18,smoothstep(.12,.86,n));
}
