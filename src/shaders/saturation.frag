// Same 3x3 CTM as cybriq/saturation cmsaturation.pl:
//   s = (1 - amount) / 3
//   [s+amount, s, s; s, s+amount, s; s, s, s+amount]
// Applied in the compositor because Wayland clients cannot set DRM CTM.
//
// No #version here — KWin prepends it. Plasma 6.8 KWin is GLES-only
// (#version 300 es); `varying` / texture2D / gl_FragColor are illegal.
//
// Closer to CRTC CTM than the first shader: matrix in ~sRGB linear
// (gamma 2.2), no hard 0–1 clip on boosted primaries.

uniform sampler2D sampler;
uniform vec4 modulation;
uniform float saturationAmount;
in vec2 texcoord0;
out vec4 fragColor;

void main()
{
    vec4 tex = texture(sampler, texcoord0);
    float alpha = max(tex.a, 0.001);
    vec3 color = pow(max(tex.rgb / alpha, vec3(0.0)), vec3(2.2));

    float s = (1.0 - saturationAmount) / 3.0;
    float d = s + saturationAmount;
    vec3 outc = vec3(
        d * color.r + s * color.g + s * color.b,
        s * color.r + d * color.g + s * color.b,
        s * color.r + s * color.g + d * color.b
    );

    outc = pow(max(outc, vec3(0.0)), vec3(1.0 / 2.2));
    fragColor = vec4(outc * alpha, tex.a) * modulation;
}
