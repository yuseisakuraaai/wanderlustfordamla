#include <SwiftUI/SwiftUI_Metal.h>
#include <metal_stdlib>
using namespace metal;

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * valueNoise(p);
        p *= 2.03;
        amplitude *= 0.5;
    }
    return value;
}

[[ stitchable ]] half4 grainEffect(float2 pos, half4 color, float scale, float intensity) {
    float n = fbm(pos * scale * 0.018);
    float grain = (n - 0.5) * 2.0 * intensity;
    half3 rgb = color.rgb + half3(grain);
    return half4(clamp(rgb, half3(0.0), half3(1.0)), color.a);
}

[[ stitchable ]] half4 fineGrain(float2 pos, half4 color, float intensity) {
    if (color.a < 0.001) { return color; }
    float n = hash21(pos) - 0.5;
    half3 rgb = clamp(color.rgb + half3(half(n) * half(intensity)), 0.0h, 1.0h);
    return half4(rgb, color.a);
}

[[ stitchable ]] half4 inkDistress(float2 pos, half4 color, float scale, float amount) {
    float low = fbm(pos * scale * 0.025);
    float high = valueNoise(pos * scale * 0.19);
    float n = mix(low, high, 0.38);
    float keep = smoothstep(amount - 0.10, amount + 0.10, n);
    return half4(color.rgb, color.a * half(keep));
}

[[ stitchable ]] half4 foilSheen(float2 pos, half4 color, float2 size, float offset, float width) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = pos / safeSize;
    float diagonal = (uv.x + uv.y) * 0.7071;
    float center = offset;
    float sigma = max(width, 0.001);
    float highlight = exp(-pow((diagonal - center) / sigma, 2.0));
    half3 sheen = half3(0.28, 0.22, 0.10) * half(highlight);
    return half4(clamp(color.rgb + sheen, half3(0.0), half3(1.0)), color.a);
}
