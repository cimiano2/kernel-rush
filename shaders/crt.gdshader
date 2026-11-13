// Pós-processamento estilo monitor CRT, aplicado num ColorRect que cobre a tela.
// Baseado no padrão "CRT Effect" da skill godot-shader, adaptado para o Godot 4:
// num ColorRect, TEXTURE não é a tela; é preciso ler hint_screen_texture com SCREEN_UV.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Curvatura do vidro (mantida baixa para não atrapalhar os cliques nas bordas).
uniform float curvature : hint_range(0.0, 0.2, 0.005) = 0.03;
// Intensidade e densidade das linhas de varredura.
uniform float scanline_intensity : hint_range(0.0, 0.5, 0.01) = 0.07;
uniform float scanline_count : hint_range(100.0, 1000.0, 10.0) = 360.0;
// Escurecimento nas bordas.
uniform float vignette_power : hint_range(0.0, 1.0, 0.01) = 0.25;
// Separação RGB base.
uniform float aberration : hint_range(0.0, 0.01, 0.0005) = 0.001;
// Oscilação leve de brilho.
uniform float flicker : hint_range(0.0, 0.1, 0.005) = 0.012;
// 0 = estável, 1 = sistema colapsando. Controlado pelo jogo (satisfação baixa / kernel panic).
uniform float glitch : hint_range(0.0, 1.0, 0.01) = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// distorção de barril
	vec2 uv = SCREEN_UV - 0.5;
	uv *= 1.0 + dot(uv, uv) * curvature;
	uv += 0.5;

	// glitch: faixas horizontais deslocadas que mudam ~12x por segundo
	float frame = floor(TIME * 12.0);
	float band = floor(uv.y * 36.0);
	float hit = step(1.0 - glitch * 0.3, rand(vec2(band, frame)));
	uv.x += hit * (rand(vec2(band, frame + 3.0)) - 0.5) * 0.05 * glitch;

	// aberração cromática (aumenta com o glitch)
	float ab = aberration + glitch * 0.003;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ab, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ab, 0.0)).b;

	// linhas de varredura
	float s = sin(uv.y * scanline_count * PI) * 0.5 + 0.5;
	col *= 1.0 - scanline_intensity * s;

	// vinheta
	float v = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
	col *= clamp(pow(16.0 * v, vignette_power), 0.0, 1.0);

	// cintilação + ruído extra durante glitch
	col *= 1.0 - flicker * rand(vec2(frame, 0.0));
	col += glitch * 0.08 * rand(uv * 400.0 + frame);

	// fora da tela curva: preto
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		col = vec3(0.0);
	}
	COLOR = vec4(col, 1.0);
}
