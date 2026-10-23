//
//  TopographyShader.swift
//  WhatTheFlight
//
//  The Metal source for the contour map behind the radar (`TopographyRenderer`).
//  `topographyHeight` builds a height field once per style and size from simplex fBm;
//  `topographyContours` draws one line per elevation from it, anti-aliased by the field's
//  own screen-space derivative, so lines stay crisp at any size and never cross or touch.
//  Tide only shifts which heights get a line, so a moving frame costs the same as a still one.
//
//  It's compiled at runtime (`makeLibrary(source:)`, cached by the system after the first
//  launch) so building the app doesn't need Xcode's separately downloaded Metal Toolchain.
//

#if os(iOS) || os(tvOS)
enum TopographyShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// MARK: - Noise

// 3D simplex noise: Ashima Arts / Stefan Gustavson (MIT).
static float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
static float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

static float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);
    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);
    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;
    i = mod289(i);
    float4 p = permute(permute(permute(
        i.z + float4(0.0, i1.z, i2.z, 1.0))
      + i.y + float4(0.0, i1.y, i2.y, 1.0))
      + i.x + float4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    float3 ns = n_ * D.wyz - D.xzx;
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);
    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);
    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), float4(0.0));
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

/// Fractal noise. A gain under 0.5 keeps the fine octaves quiet: long smooth lines, no speckle.
static float fbm(float2 p, float z, int octaves, float gain) {
    const float2x2 rot = float2x2(0.8, -0.6, 0.6, 0.8);
    float a = 0.5, s = 0.0, n = 0.0;
    for (int i = 0; i < octaves; i++) {
        s += a * snoise(float3(p, z + float(i) * 1.7));
        n += a;
        p = rot * p * 2.03 + float2(11.3, -7.1);
        a *= gain;
    }
    return s / n;
}

/// Sharp crests for Relief's mountains.
static float ridged(float2 p, float z, int octaves) {
    const float2x2 rot = float2x2(0.8, -0.6, 0.6, 0.8);
    float a = 0.5, s = 0.0, n = 0.0;
    for (int i = 0; i < octaves; i++) {
        float r = 1.0 - abs(snoise(float3(p, z + float(i) * 2.3)));
        s += a * r * r;
        n += a;
        p = rot * p * 2.03 + float2(5.1, 3.3);
        a *= 0.5;
    }
    return s / n;
}

/// Style indices match `TopographyRenderer.Look.shaderIndex`.
static float terrainHeight(float2 p, float z, int style) {
    switch (style) {
    case 0: // Remaster: today's big gentle hills
        return fbm(p * 0.75, z, 3, 0.38);
    case 1: // Survey
        return fbm(p * 0.8, z, 4, 0.45);
    case 2: { // Highlands: domain-warped ridges and valleys
        float2 w = p * 0.8;
        float2 q = float2(fbm(w, z, 3, 0.5), fbm(w + float2(5.2, 1.3), z, 3, 0.5));
        return fbm(w + 0.8 * q, z, 4, 0.47);
    }
    default: // Relief
        return 0.65 * fbm(p * 0.8, z, 4, 0.45) + 0.35 * (ridged(p * 0.6, z, 3) - 0.55);
    }
}

// MARK: - Terrain (once per style and size)

struct TerrainUniforms {
    float2 originPt;     // terrain point at the top-left corner of texel (0, 0)
    float ptPerTexel;
    float featurePt;     // size of the largest hills, in points
    float seed;
    int style;
};

kernel void topographyHeight(texture2d<float, access::write> height [[texture(0)]],
                             constant TerrainUniforms &u [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= height.get_width() || gid.y >= height.get_height()) return;
    float2 pt = u.originPt + (float2(gid) + 0.5) * u.ptPerTexel;
    float2 p = pt / u.featurePt + float2(u.seed * 17.17, u.seed * -9.31);
    height.write(float4(terrainHeight(p, u.seed * 1.37, u.style)), gid);
}

/// Relief's hill shading, lit from the upper left, from the stored heights.
kernel void topographyShade(texture2d<float, access::read> height [[texture(0)]],
                            texture2d<float, access::write> shade [[texture(1)]],
                            constant TerrainUniforms &u [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    uint w = height.get_width(), h = height.get_height();
    if (gid.x >= w || gid.y >= h) return;
    uint2 left = uint2(gid.x > 0 ? gid.x - 1 : 0, gid.y);
    uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
    uint2 up = uint2(gid.x, gid.y > 0 ? gid.y - 1 : 0);
    uint2 down = uint2(gid.x, min(gid.y + 1, h - 1));
    // Slope per hill size, so the shading looks the same whatever `featurePt` is.
    float2 slope = float2(height.read(right).r - height.read(left).r,
                          height.read(down).r - height.read(up).r) / (2.0 * u.ptPerTexel) * u.featurePt;
    float3 normal = normalize(float3(-slope * 0.55, 1.0));
    float3 light = normalize(float3(-1.0, -1.0, 1.25));
    shade.write(float4(dot(normal, light) - light.z), gid);
}

// MARK: - Contours (every frame)

struct ContourUniforms {
    float4 paper;
    float4 ink;
    float4 shadeTint;
    float2 heightSize;   // texels
    float pxPerPt;       // drawn pixels per terrain point
    float levels;        // contour lines per unit of height
    float minorWidthPt;
    float indexWidthPt;
    float minorAlpha;
    float indexAlpha;
    float shift;         // Tide, in contour levels
    float thinFloor;     // keeps sub-pixel lines visible in thumbnails
    float shadeStrength; // 0: no hill shading
    int hasIndex;        // every fifth line heavier
    int dark;
};

struct ContourVertex {
    float4 position [[position]];
    float2 uv;
};

vertex ContourVertex topographyVertex(uint vid [[vertex_id]]) {
    float2 corner = float2(float((vid << 1) & 2), float(vid & 2));
    ContourVertex out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(corner.x, 1.0 - corner.y);
    return out;
}

/// 32-bit float textures aren't filterable on every Apple GPU, so interpolate by hand.
static float bilinear(texture2d<float, access::read> tex, float2 texel) {
    float2 t = texel - 0.5;
    float2 f = fract(t);
    int2 i0 = int2(floor(t));
    int2 last = int2(int(tex.get_width()) - 1, int(tex.get_height()) - 1);
    float a = tex.read(uint2(clamp(i0, int2(0), last))).r;
    float b = tex.read(uint2(clamp(i0 + int2(1, 0), int2(0), last))).r;
    float c = tex.read(uint2(clamp(i0 + int2(0, 1), int2(0), last))).r;
    float d = tex.read(uint2(clamp(i0 + int2(1, 1), int2(0), last))).r;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

fragment float4 topographyContours(ContourVertex in [[stage_in]],
                                   texture2d<float, access::read> height [[texture(0)]],
                                   texture2d<float> shade [[texture(1)]],
                                   constant ContourUniforms &u [[buffer(0)]]) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float h = bilinear(height, in.uv * u.heightSize);
    float v = h * u.levels + u.shift;
    float fw = max(fwidth(v), 1e-5);
    float distance = abs(fract(v + 0.5) - 0.5) / fw;   // pixels to the nearest line
    float n = floor(v + 0.5);
    bool isIndex = u.hasIndex != 0 && (n - 5.0 * floor(n / 5.0)) < 0.5;
    float want = (isIndex ? u.indexWidthPt : u.minorWidthPt) * u.pxPerPt;
    float width = max(want, 0.85);
    float cover = clamp(width * 0.5 + 0.5 - distance, 0.0, 1.0) * max(u.thinFloor, min(1.0, want / 0.85));
    // Where lines bunch tighter than a few pixels (cliffs), let them fade instead of moiré.
    float crowd = 1.0 - smoothstep(0.28, 0.65, fw);
    float alpha = cover * crowd * (isIndex ? u.indexAlpha : u.minorAlpha);

    float3 color = u.paper.rgb;
    if (u.shadeStrength > 0.0) {
        float s = shade.sample(linear, in.uv).r;
        color = u.dark != 0 ? color + u.shadeTint.rgb * s * u.shadeStrength : color * (1.0 + s * u.shadeStrength);
    }
    return float4(clamp(mix(color, u.ink.rgb, alpha), 0.0, 1.0), 1.0);
}
"""#
}
#endif
