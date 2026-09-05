// Same 3x3 CTM as cybriq/saturation cmsaturation.pl:
//   s = (1 - amount) / 3
//   [s+amount, s, s; s, s+amount, s; s, s, s+amount]
// Applied in the compositor because Wayland clients cannot set DRM CTM.

uniform sampler2D sampler;
uniform vec4 modulation;
uniform float saturationAmount;
varying vec2 texcoord0;

void main()
{
    vec4 tex = texture2D(sampler, texcoord0);
    float alpha = max(tex.a, 0.001);
    vec3 color = tex.rgb / alpha;

    float s = (1.0 - saturationAmount) / 3.0;
    float d = s + saturationAmount;
    vec3 outc = vec3(
        d * color.r + s * color.g + s * color.b,
        s * color.r + d * color.g + s * color.b,
        s * color.r + s * color.g + d * color.b
    );

    gl_FragColor = vec4(clamp(outc, 0.0, 1.0) * alpha, tex.a) * modulation;
}
