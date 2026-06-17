# Metal Shader Techniques

Shader math and algorithms in Metal Shading Language. These techniques are language-agnostic math adapted to MSL syntax — usable in fragment shaders, compute kernels, and SwiftUI shader effects.

---

## Signed Distance Functions (2D)

SDFs return the distance from a point to the nearest surface. Negative = inside, positive = outside.

### Primitives

```metal
// Circle
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

// Box
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Rounded box
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 d = abs(p) - b + r;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Line segment
float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Equilateral triangle
float sdTriangle(float2 p, float r) {
    const float k = sqrt(3.0);
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0) p = float2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}
```

### Operations

```metal
// Union
float opUnion(float d1, float d2) { return min(d1, d2); }

// Subtraction
float opSubtraction(float d1, float d2) { return max(-d1, d2); }

// Intersection
float opIntersection(float d1, float d2) { return max(d1, d2); }

// Smooth union (soft blend between shapes)
float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

// Smooth subtraction
float opSmoothSubtraction(float d1, float d2, float k) {
    float h = clamp(0.5 - 0.5 * (d2 + d1) / k, 0.0, 1.0);
    return mix(d2, -d1, h) + k * h * (1.0 - h);
}

// Round (expand shape outline)
float opRound(float d, float r) { return d - r; }

// Annular (ring / outline)
float opAnnular(float d, float r) { return abs(d) - r; }
```

---

## Signed Distance Functions (3D)

### Primitives

```metal
float sdSphere(float3 p, float r) {
    return length(p) - r;
}

float sdBox3D(float3 p, float3 b) {
    float3 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float sdCapsule(float3 p, float3 a, float3 b, float r) {
    float3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

float sdCylinder(float3 p, float h, float r) {
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdPlane(float3 p, float3 n, float h) {
    return dot(p, n) + h;
}
```

### 3D Operations

```metal
// Repeat in space (infinite tiling)
float3 opRepeat(float3 p, float3 period) {
    return fmod(p + 0.5 * period, period) - 0.5 * period;
}

// Repeat with limited count
float3 opRepeatLimited(float3 p, float period, float3 limit) {
    return p - period * clamp(round(p / period), -limit, limit);
}

// Twist around Y axis
float3 opTwist(float3 p, float k) {
    float c = cos(k * p.y);
    float s = sin(k * p.y);
    float2x2 m = float2x2(c, -s, s, c);
    return float3(m * p.xz, p.y);
}

// Bend around X axis
float3 opBend(float3 p, float k) {
    float c = cos(k * p.x);
    float s = sin(k * p.x);
    float2x2 m = float2x2(c, -s, s, c);
    float2 bent = m * float2(p.x, p.y);
    return float3(bent.x, bent.y, p.z);
}
```

---

## Ray Marching

Sphere-tracing algorithm for rendering SDFs. The core loop for 3D SDF scenes.

```metal
struct RayMarchResult {
    float distance;
    int steps;
    bool hit;
};

RayMarchResult rayMarch(float3 ro, float3 rd, int maxSteps, float maxDist, float epsilon) {
    float t = 0.0;
    for (int i = 0; i < maxSteps; i++) {
        float3 p = ro + rd * t;
        float d = sceneSDF(p);  // Your scene's distance function
        if (d < epsilon) return { t, i, true };
        t += d;
        if (t > maxDist) break;
    }
    return { t, maxSteps, false };
}
```

### Normal Estimation

```metal
float3 estimateNormal(float3 p, float epsilon) {
    float2 e = float2(epsilon, 0.0);
    return normalize(float3(
        sceneSDF(p + e.xyy) - sceneSDF(p - e.xyy),
        sceneSDF(p + e.yxy) - sceneSDF(p - e.yxy),
        sceneSDF(p + e.yyx) - sceneSDF(p - e.yyx)
    ));
}
```

### Camera Setup

```metal
float3x3 lookAt(float3 eye, float3 target, float3 up) {
    float3 f = normalize(target - eye);
    float3 s = normalize(cross(f, up));
    float3 u = cross(s, f);
    return float3x3(s, u, -f);
}

// Usage in fragment shader:
// float3 rd = normalize(lookAt(eye, target, float3(0,1,0)) * float3(uv, -focalLength));
```

---

## Procedural Noise

### Value Noise

```metal
float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);  // Smoothstep interpolation

    float a = hash(i);
    float b = hash(i + float2(1, 0));
    float c = hash(i + float2(0, 1));
    float d = hash(i + float2(1, 1));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
```

### Gradient Noise (Perlin-style)

```metal
float2 hashGradient(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)),
               dot(p, float2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

float gradientNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    return mix(mix(dot(hashGradient(i), f),
                   dot(hashGradient(i + float2(1, 0)), f - float2(1, 0)), u.x),
               mix(dot(hashGradient(i + float2(0, 1)), f - float2(0, 1)),
                   dot(hashGradient(i + float2(1, 1)), f - float2(1, 1)), u.x), u.y);
}
```

### Fractal Brownian Motion (FBM)

```metal
float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * gradientNoise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}
```

### Voronoi / Cellular Noise

```metal
struct VoronoiResult {
    float distance;   // Distance to nearest cell centre
    float2 cellId;    // ID of nearest cell
    float edgeDist;   // Distance to nearest edge
};

VoronoiResult voronoi(float2 p) {
    float2 n = floor(p);
    float2 f = fract(p);

    float minDist = 8.0;
    float secondDist = 8.0;
    float2 closestCell;

    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 g = float2(i, j);
            float2 o = float2(hash(n + g), hash(n + g + 17.0));  // Random offset
            float2 diff = g + o - f;
            float d = dot(diff, diff);
            if (d < minDist) {
                secondDist = minDist;
                minDist = d;
                closestCell = n + g;
            } else if (d < secondDist) {
                secondDist = d;
            }
        }
    }
    return { sqrt(minDist), closestCell, sqrt(secondDist) - sqrt(minDist) };
}
```

---

## Lighting Models

### Blinn-Phong

```metal
float3 blinnPhong(float3 normal, float3 lightDir, float3 viewDir,
                  float3 albedo, float3 lightColor, float shininess) {
    // Diffuse
    float diff = max(dot(normal, lightDir), 0.0);

    // Specular
    float3 halfDir = normalize(lightDir + viewDir);
    float spec = pow(max(dot(normal, halfDir), 0.0), shininess);

    // Ambient
    float3 ambient = 0.05 * albedo;

    return ambient + diff * albedo * lightColor + spec * lightColor;
}
```

### PBR (Cook-Torrance)

```metal
// Normal distribution function (GGX/Trowbridge-Reitz)
float distributionGGX(float3 N, float3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    return a2 / (M_PI_F * denom * denom);
}

// Geometry function (Schlick-GGX)
float geometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float geometrySmith(float3 N, float3 V, float3 L, float roughness) {
    return geometrySchlickGGX(max(dot(N, V), 0.0), roughness)
         * geometrySchlickGGX(max(dot(N, L), 0.0), roughness);
}

// Fresnel (Schlick approximation)
float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Full PBR fragment
float3 pbrLighting(float3 N, float3 V, float3 L, float3 albedo,
                   float metallic, float roughness, float3 lightColor) {
    float3 H = normalize(V + L);
    float3 F0 = mix(float3(0.04), albedo, metallic);

    float D = distributionGGX(N, H, roughness);
    float G = geometrySmith(N, V, L, roughness);
    float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    float3 numerator = D * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular = numerator / denominator;

    float3 kD = (1.0 - F) * (1.0 - metallic);
    float NdotL = max(dot(N, L), 0.0);

    return (kD * albedo / M_PI_F + specular) * lightColor * NdotL;
}
```

### Soft Shadows (Ray Marched)

```metal
float softShadow(float3 ro, float3 rd, float mint, float maxt, float k) {
    float result = 1.0;
    float t = mint;
    for (int i = 0; i < 64; i++) {
        float h = sceneSDF(ro + rd * t);
        if (h < 0.001) return 0.0;
        result = min(result, k * h / t);
        t += h;
        if (t > maxt) break;
    }
    return result;
}
```

### Ambient Occlusion (Ray Marched)

```metal
float ambientOcclusion(float3 p, float3 n, int steps, float stepSize) {
    float ao = 0.0;
    float weight = 1.0;
    for (int i = 1; i <= steps; i++) {
        float dist = float(i) * stepSize;
        float d = sceneSDF(p + n * dist);
        ao += weight * (dist - d);
        weight *= 0.5;
    }
    return 1.0 - clamp(ao, 0.0, 1.0);
}
```

---

## Post-Processing Effects

Fragment shader snippets for full-screen post-processing passes. Apply via render-to-texture then full-screen quad.

### Vignette

```metal
float3 applyVignette(float3 color, float2 uv, float intensity) {
    float dist = distance(uv, float2(0.5));
    float vignette = smoothstep(0.8, 0.4, dist * intensity);
    return color * vignette;
}
```

### Bloom (Threshold + Blur)

```metal
// Step 1: Extract bright pixels
float3 bloomThreshold(float3 color, float threshold) {
    float brightness = dot(color, float3(0.2126, 0.7152, 0.0722));
    return brightness > threshold ? color : float3(0.0);
}

// Step 2: Gaussian blur (separable — run horizontal then vertical)
float3 gaussianBlur(texture2d<float> tex, sampler s, float2 uv, float2 direction, int samples) {
    float3 result = float3(0.0);
    float totalWeight = 0.0;
    for (int i = -samples; i <= samples; i++) {
        float weight = exp(-0.5 * float(i * i) / float(samples));
        float2 offset = direction * float(i);
        result += tex.sample(s, uv + offset).rgb * weight;
        totalWeight += weight;
    }
    return result / totalWeight;
}

// Step 3: Composite
float3 applyBloom(float3 scene, float3 bloom, float intensity) {
    return scene + bloom * intensity;
}
```

### Tone Mapping

```metal
// ACES filmic tone mapping
float3 acesToneMap(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// Reinhard
float3 reinhardToneMap(float3 color) {
    return color / (1.0 + color);
}
```

### Chromatic Aberration

```metal
float3 chromaticAberration(texture2d<float> tex, sampler s, float2 uv, float strength) {
    float2 offset = (uv - 0.5) * strength;
    float r = tex.sample(s, uv + offset).r;
    float g = tex.sample(s, uv).g;
    float b = tex.sample(s, uv - offset).b;
    return float3(r, g, b);
}
```

### Film Grain

```metal
float3 applyGrain(float3 color, float2 uv, float time, float intensity) {
    float noise = fract(sin(dot(uv + fract(time), float2(12.9898, 78.233))) * 43758.5453);
    return color + (noise - 0.5) * intensity;
}
```

---

## Domain Warping

Distort input coordinates using noise to create organic, flowing patterns.

```metal
// Basic domain warp
float domainWarp(float2 p) {
    float2 q = float2(fbm(p, 4), fbm(p + float2(5.2, 1.3), 4));
    return fbm(p + 4.0 * q, 4);
}

// Double domain warp (more complex patterns)
float domainWarp2(float2 p, float time) {
    float2 q = float2(fbm(p + float2(0.0, 0.0), 4),
                      fbm(p + float2(5.2, 1.3), 4));
    float2 r = float2(fbm(p + 4.0 * q + float2(1.7, 9.2) + 0.15 * time, 4),
                      fbm(p + 4.0 * q + float2(8.3, 2.8) + 0.126 * time, 4));
    return fbm(p + 4.0 * r, 4);
}
```

---

## Colour Utilities

### Cosine Colour Palettes

Generate smooth colour ramps from four parameters — extremely compact.

```metal
float3 cosinePalette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318 * (c * t + d));
}

// Preset: rainbow
// cosinePalette(t, float3(0.5), float3(0.5), float3(1.0), float3(0.0, 0.33, 0.67))

// Preset: sunset
// cosinePalette(t, float3(0.5,0.5,0.5), float3(0.5,0.5,0.5), float3(1.0,0.7,0.4), float3(0.0,0.15,0.20))

// Preset: ocean
// cosinePalette(t, float3(0.5,0.5,0.5), float3(0.5,0.5,0.5), float3(2.0,1.0,0.0), float3(0.5,0.20,0.25))
```

### Colour Space Conversions

```metal
// Linear to sRGB
float3 linearToSRGB(float3 color) {
    return pow(color, 1.0 / 2.2);
}

// sRGB to Linear
float3 sRGBToLinear(float3 color) {
    return pow(color, 2.2);
}

// RGB to HSV
float3 rgbToHsv(float3 c) {
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB
float3 hsvToRgb(float3 c) {
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
```

---

## Volumetric Rendering

For fog, clouds, smoke, and atmospheric effects.

```metal
struct VolumeResult {
    float3 color;
    float transmittance;
};

VolumeResult rayMarchVolume(float3 ro, float3 rd, float maxDist, int steps,
                            float density, float3 lightDir, float3 lightColor) {
    float stepSize = maxDist / float(steps);
    float3 accColor = float3(0.0);
    float transmittance = 1.0;

    for (int i = 0; i < steps; i++) {
        float3 p = ro + rd * (float(i) + 0.5) * stepSize;

        // Sample density at point (use noise for clouds/smoke)
        float d = sampleDensity(p) * density;
        if (d < 0.001) continue;

        // Beer-Lambert absorption
        float absorption = exp(-d * stepSize);

        // Simple light contribution
        float lightAtten = softShadow(p, lightDir, 0.1, 10.0, 8.0);
        float3 luminance = lightColor * lightAtten * d;

        accColor += transmittance * luminance * stepSize;
        transmittance *= absorption;

        if (transmittance < 0.01) break;  // Early exit
    }

    return { accColor, transmittance };
}
```

---

## GPU Particle Systems (Compute)

Use compute shaders for GPU-driven particle simulation.

### Particle Struct (Shared Swift + MSL)

```metal
struct Particle {
    float2 position;
    float2 velocity;
    float life;
    float maxLife;
    float4 color;
};
```

### Update Kernel

```metal
kernel void updateParticles(
    device Particle *particles [[buffer(0)]],
    constant float &deltaTime [[buffer(1)]],
    constant float2 &gravity [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    Particle p = particles[id];
    if (p.life <= 0.0) return;

    p.velocity += gravity * deltaTime;
    p.position += p.velocity * deltaTime;
    p.life -= deltaTime;
    p.color.a = p.life / p.maxLife;  // Fade out

    particles[id] = p;
}
```

### Emit Kernel

```metal
kernel void emitParticles(
    device Particle *particles [[buffer(0)]],
    constant float2 &emitPosition [[buffer(1)]],
    constant uint &startIndex [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) return;
    uint idx = startIndex + id;

    // Pseudo-random direction
    float angle = hash(float2(float(idx), 0.0)) * 2.0 * M_PI_F;
    float speed = 50.0 + hash(float2(float(idx), 1.0)) * 100.0;

    Particle p;
    p.position = emitPosition;
    p.velocity = float2(cos(angle), sin(angle)) * speed;
    p.life = 1.0 + hash(float2(float(idx), 2.0)) * 2.0;
    p.maxLife = p.life;
    p.color = float4(1.0, 0.8, 0.3, 1.0);

    particles[idx] = p;
}
```

---

## Fractal Rendering

### Mandelbrot Set

```metal
float mandelbrot(float2 c, int maxIter) {
    float2 z = float2(0.0);
    int i;
    for (i = 0; i < maxIter; i++) {
        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        if (dot(z, z) > 4.0) break;
    }
    // Smooth iteration count
    if (i < maxIter) {
        float log_zn = log(dot(z, z)) / 2.0;
        float nu = log(log_zn / log(2.0)) / log(2.0);
        return float(i) + 1.0 - nu;
    }
    return float(maxIter);
}
```

### Julia Set

```metal
float julia(float2 z, float2 c, int maxIter) {
    for (int i = 0; i < maxIter; i++) {
        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        if (dot(z, z) > 4.0) {
            float log_zn = log(dot(z, z)) / 2.0;
            float nu = log(log_zn / log(2.0)) / log(2.0);
            return float(i) + 1.0 - nu;
        }
    }
    return float(maxIter);
}
```

---

## Polar and UV Manipulation

```metal
// Cartesian to polar
float2 toPolar(float2 p) {
    return float2(length(p), atan2(p.y, p.x));
}

// Polar to cartesian
float2 fromPolar(float2 polar) {
    return polar.x * float2(cos(polar.y), sin(polar.y));
}

// Kaleidoscope (angular symmetry)
float2 kaleidoscope(float2 p, float segments) {
    float2 polar = toPolar(p);
    float segmentAngle = 2.0 * M_PI_F / segments;
    polar.y = fmod(polar.y, segmentAngle);
    if (polar.y > segmentAngle * 0.5) polar.y = segmentAngle - polar.y;
    return fromPolar(polar);
}

// Rotate UV
float2 rotate2D(float2 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}
```

---

## Performance Tips

| Technique | Guideline |
|---|---|
| `half` precision | Use `half`, `half3`, `half4` for colour math — 2x throughput on Apple GPUs |
| Loop unrolling | Keep ray march steps reasonable (64-128 for quality, 32 for real-time) |
| Early exit | Break from loops when transmittance < threshold or distance > max |
| Avoid `sin`/`cos` in tight loops | Precompute or use polynomial approximations |
| SDF combinations | Flatten nested smooth unions — each adds cost |
| Noise octaves | 3-4 octaves of FBM is usually enough for real-time; 6+ for offline |
| Texture lookups | Use precomputed noise textures instead of procedural noise where possible |
| Threadgroup size | For 2D image work, use 16x16 threadgroups (256 threads) |
