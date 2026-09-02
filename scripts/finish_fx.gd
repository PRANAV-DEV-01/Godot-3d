extends CanvasLayer
## Finish-beacon screen effect — a brief, tasteful pulse: chromatic edge
## aberration + soft vignette for ~1.2 s after the beacon is hit, then a
## clean fade to nothing. The overlay ignores mouse input so it never eats
## clicks, and is hidden whenever inactive.

var _rect: ColorRect
var _mat: ShaderMaterial
var _active := false
var _t := 0.0

const PULSE_DUR := 1.4


func _ready() -> void:
	layer = 25
	add_to_group("finish_listeners")
	_build()


func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = _make_shader()
	_mat.set_shader_parameter("chromatic", 0.0)
	_mat.set_shader_parameter("vignette", 0.0)

	_rect = ColorRect.new()
	_rect.name = "FinishPulse"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)


func on_finish() -> void:
	_active = true
	_t = 0.0
	_rect.visible = true


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	if _t >= PULSE_DUR:
		_active = false
		_rect.visible = false
		_mat.set_shader_parameter("chromatic", 0.0)
		_mat.set_shader_parameter("vignette", 0.0)
		return

	var u := _t / PULSE_DUR
	var env := 1.0
	if u < 0.18:
		env = u / 0.18
	else:
		env = maxf(1.0 - (u - 0.18) / (1.0 - 0.18), 0.0)
	_mat.set_shader_parameter("chromatic", 0.0055 * env)
	_mat.set_shader_parameter("vignette", 0.34 * env)


func _make_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable;
uniform float chromatic : hint_range(0.0, 0.02) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = normalize((uv - vec2(0.5)) * vec2(1.25, 1.0));
	float r = texture(screen_tex, uv + dir * chromatic).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - dir * chromatic).b;
	vec3 col = vec3(r, g, b);
	float d = distance(uv, vec2(0.5));
	float vig = smoothstep(0.35, 0.9, d * 1.35);
	col *= 1.0 - vignette * vig;
	COLOR = vec4(col, 1.0);
}
"""
	return s