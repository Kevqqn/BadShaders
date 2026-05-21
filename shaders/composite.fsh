#version 430 compatibility

layout(location = 0) out vec4 fragColor;

uniform sampler2D colortex0;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float frameTimeCounter;
uniform float sunAngle;
uniform float rainStrength;
uniform bool hideGUI;
uniform int frameCounter;

in vec2 uv;

float ditherGradNoiseTemporal() {
    return fract(52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y + 0.00623715 * float(frameCounter) * 0.31));
}

#define CLOUD_STEPS       32
#define CLOUD_COVERAGE    0.67
#define CLOUD_DENSITY     4.0
#define BADAPPLE_REGION   256.0
#define BADAPPLE_FPS      16.0
#define BADAPPLE_FRAMES   3504
#define ATLAS_COLS        60
#define ATLAS_ROWS        60
#define CLOUD_BOTTOM      160.0
#define CLOUD_TOP         260.0
#define CLOUD_THICKNESS   (CLOUD_TOP - CLOUD_BOTTOM)

float hash(vec3 p) {
    p  = fract(p * vec3(127.1, 311.7, 74.7));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash(i),            hash(i+vec3(1,0,0)), f.x),
            mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x), f.y),
        mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),
            mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x), f.y),
        f.z);
}

float fbmShape(vec3 p) {
    float v = 0.0, a = 0.5;
    v += a * noise3(p); p *= 2.03; a *= 0.5;
    v += a * noise3(p); p *= 2.03; a *= 0.5;
    v += a * noise3(p); p *= 2.03; a *= 0.5;
    v += a * noise3(p); p *= 2.03; a *= 0.5;
    v += a * noise3(p);
    return v;
}

float fbmDetail(vec3 p) {
    float v = 0.0, a = 0.5;
    v += a * noise3(p); p *= 2.1; a *= 0.5;
    v += a * noise3(p); p *= 2.1; a *= 0.5;
    v += a * noise3(p);
    return v;
}

vec3 getSkyColor(vec3 rayDir, vec3 sunDir) {
    float horizon    = clamp(1.0 - rayDir.y, 0.0, 1.0);
    float sunDot     = clamp(dot(rayDir, sunDir), 0.0, 1.0);
    float goldenHour = clamp(1.0 - abs(sunDir.y) * 3.0, 0.0, 1.0);
          goldenHour = goldenHour * goldenHour;
    float night      = clamp(-sunDir.y * 2.0, 0.0, 1.0);

    vec3 zenith   = mix(vec3(0.1, 0.3, 0.8),   vec3(0.01, 0.01, 0.04), night);
         zenith   = mix(zenith, vec3(0.05, 0.1, 0.3), goldenHour * 0.4);
    vec3 horizCol = mix(vec3(0.6, 0.75, 0.95), vec3(0.02, 0.02, 0.06), night);
         horizCol = mix(horizCol, vec3(1.0, 0.45, 0.1), goldenHour * 0.8);

    vec3 sky = mix(zenith, horizCol, pow(horizon, 3.0));

    vec3 sunColor = mix(vec3(1.0, 0.95, 0.8), vec3(1.0, 0.4, 0.05), goldenHour);
    sky += sunColor * pow(sunDot, 8.0) * mix(0.4, 1.2, goldenHour) * (1.0 - night);

    sky = mix(sky, vec3(dot(sky, vec3(0.299, 0.587, 0.114))) * 0.6, rainStrength * 0.7);
    return max(sky, vec3(0.0));
}

vec2 sampleBadApple(vec2 worldXZ) {
    if (!hideGUI) return vec2(0.5, 0.0);

    vec2 regionUV = (worldXZ - cameraPosition.xz) / BADAPPLE_REGION + 0.5;

    vec2 edgeFade = smoothstep(0.0, 0.2, regionUV) * smoothstep(1.0, 0.8, regionUV);
    float regionW = edgeFade.x * edgeFade.y;
    if (regionW <= 0.0) return vec2(0.5, 0.0);

    vec2 warpPos = regionUV * 8.0 + frameTimeCounter * 0.02;
    vec2 warp    = vec2(
        fbmShape(vec3(warpPos, 0.0)) * 2.0 - 1.0,
        fbmShape(vec3(warpPos + 3.7, 1.3)) * 2.0 - 1.0
    ) * 0.04;
    regionUV    += warp;
    regionUV     = clamp(regionUV, 0.0, 1.0);
    regionUV.x   = 1.0 - regionUV.x;

    int  frame     = int(mod(frameTimeCounter * BADAPPLE_FPS, float(BADAPPLE_FRAMES)));
    int  col       = int(mod(float(frame), float(ATLAS_COLS)));
    int  row       = frame / ATLAS_COLS;
    vec2 frameBase = vec2(float(col), float(row)) / vec2(float(ATLAS_COLS), float(ATLAS_ROWS));
    vec2 frameUV   = frameBase + regionUV / vec2(float(ATLAS_COLS), float(ATLAS_ROWS));

    vec2  px  = vec2(1.0) / vec2(float(ATLAS_COLS) * 256.0, float(ATLAS_ROWS) * 256.0);
    vec2  rad = px * 0.4;
    float val = 0.0;
    float wSum = 0.0;
    for (int sx = -2; sx <= 2; sx++) {
        for (int sy = -2; sy <= 2; sy++) {
            float w = 1.0 / (1.0 + float(sx*sx + sy*sy));
            val  += texture(colortex5, frameUV + vec2(float(sx), float(sy)) * rad).r * w;
            wSum += w;
        }
    }
    val /= wSum;
    return vec2(val, regionW);
}

float cloudDensity(vec3 worldPos) {
    float heightFade = smoothstep(CLOUD_BOTTOM,      CLOUD_BOTTOM + 12.0, worldPos.y)
                     * smoothstep(CLOUD_TOP,         CLOUD_TOP    - 12.0, worldPos.y);
    if (heightFade <= 0.0) return 0.0;

    float h    = (worldPos.y - CLOUD_BOTTOM) / CLOUD_THICKNESS;
    vec3  wind = vec3(frameTimeCounter * 0.008, 0.0, frameTimeCounter * 0.003);

    float taperScale = 1.0 / (1.0 + h * 1.5);
    vec2  taperedXZ  = cameraPosition.xz + (worldPos.xz - cameraPosition.xz) * taperScale;
    vec2  maskSample = sampleBadApple(taperedXZ);
    float maskVal    = maskSample.x;
    float maskWeight = maskSample.y;

    float biasMagnitude = 0.65 * maskWeight * (1.0 - h * 0.5);
    float bias          = (maskVal * 2.0 - 1.0) * biasMagnitude;

    vec3  animPos   = worldPos * 0.003 + wind;
    float shape     = fbmShape(animPos) + bias;
    float threshold = 1.0 - CLOUD_COVERAGE;
          shape     = clamp((shape - threshold) / max(1.0 - threshold, 0.001), 0.0, 1.0);
    if (shape <= 0.0) return 0.0;

    vec3  detailPos  = worldPos * 0.012 + wind;
    float edgeFactor = 1.0 - abs(h * 2.0 - 1.0);
    shape -= fbmDetail(detailPos) * 0.45 * (1.0 - edgeFactor * 0.5);
    shape  = clamp(shape, 0.0, 1.0);
    if (shape <= 0.0) return 0.0;

    shape *= smoothstep(0.0, 0.15, h) * smoothstep(1.0, 0.5, h);

    if (maskWeight > 0.0) {
        float signedDist  = maskVal - 0.5;
        float densityRamp = smoothstep(-0.5, 0.5, signedDist * 6.0);
        shape *= mix(1.0, densityRamp, maskWeight);
    }

    return clamp(shape, 0.0, 1.0) * heightFade;
}

float lightMarch(vec3 worldPos, vec3 sunDir) {
    float stepSize = CLOUD_THICKNESS / 8.0;
    float od = 0.0;
    for (int i = 0; i < 8; i++) {
        worldPos += sunDir * stepSize;
        od       += cloudDensity(worldPos) * stepSize;
    }
    return exp(-od * CLOUD_DENSITY * 0.15);
}

vec3 getWorldRay(vec2 uv) {
    vec4 ndcPos  = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * ndcPos;
    viewPos /= viewPos.w;
    return normalize((gbufferModelViewInverse * vec4(viewPos.xyz, 0.0)).xyz);
}

vec4 marchClouds(vec3 rayOrigin, vec3 rayDir, vec3 sunDir, float sceneT) {
    if (rayDir.y < 0.001) return vec4(0.0);

    float tBottom = (CLOUD_BOTTOM - rayOrigin.y) / rayDir.y;
    float tTop    = (CLOUD_TOP    - rayOrigin.y) / rayDir.y;
    float tEnter  = min(tBottom, tTop);
    float tExit   = max(tBottom, tTop);
    if (tExit < 0.0 || tEnter > sceneT) return vec4(0.0);
    tEnter = max(tEnter, 0.0);

    float maxT     = min(tExit, sceneT);
    float stepSize = (maxT - tEnter) / float(CLOUD_STEPS);
    tEnter += stepSize * ditherGradNoiseTemporal();

    float goldenHour = clamp(1.0 - abs(sunDir.y) * 3.0, 0.0, 1.0);
          goldenHour = goldenHour * goldenHour;
    float night      = clamp(-sunDir.y * 2.0, 0.0, 1.0);

    vec3 sunColor   = mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.45, 0.1), goldenHour * 0.7);
         sunColor   = mix(sunColor, vec3(0.3, 0.35, 0.5), night);
    vec3 ambientTop = mix(vec3(0.5, 0.65, 0.9),  vec3(0.05, 0.08, 0.15), night);
    vec3 ambientBot = mix(vec3(0.3, 0.4,  0.6),  vec3(0.02, 0.03, 0.07), night);

    sunColor    = mix(sunColor,   vec3(0.55), rainStrength * 0.6);
    ambientTop  = mix(ambientTop, vec3(0.45), rainStrength * 0.6);
    ambientBot  = mix(ambientBot, vec3(0.35), rainStrength * 0.6);

    vec3  cloudColor = vec3(0.0);
    float transmit   = 1.0;

    for (int i = 0; i < CLOUD_STEPS; i++) {
        float t       = tEnter + (float(i) + 0.5) * stepSize;
        vec3  pos     = rayOrigin + rayDir * t;
        float density = cloudDensity(pos);

        if (density > 0.001) {
            float h          = clamp((pos.y - CLOUD_BOTTOM) / CLOUD_THICKNESS, 0.0, 1.0);
            float lightAtten = lightMarch(pos, sunDir);
            vec3  ambient    = mix(ambientBot, ambientTop, h);
            float cosTheta   = dot(rayDir, sunDir);
            float silver     = pow(max(cosTheta, 0.0), 6.0) * (1.0 - density) * 0.5;
            vec3  radiance   = mix(ambient, sunColor, lightAtten) + sunColor * silver;
            float absorption = density * stepSize * CLOUD_DENSITY;
            float sampleTr   = exp(-absorption);
            cloudColor      += transmit * (1.0 - sampleTr) * radiance;
            transmit        *= sampleTr;
        }

        if (transmit < 0.01) break;
    }

    return vec4(cloudColor, 1.0 - transmit);
}

void main() {
    vec3  scene = texture(colortex0, uv).rgb;
    float depth = texture(depthtex0, uv).r;
    bool  isSky = (depth >= 1.0);

    vec3 rayDir    = getWorldRay(uv);
    vec3 rayOrigin = cameraPosition;
    vec3 sunDir    = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    float sceneT   = isSky ? 1e6 : depth * 1000.0;

    vec4 clouds = vec4(0.0);
    if (rayDir.y > -0.05) {
        clouds = marchClouds(rayOrigin, rayDir, sunDir, sceneT);
    }

    vec3 base   = isSky ? getSkyColor(rayDir, sunDir) : scene;
    vec3 result = base * (1.0 - clouds.a) + clouds.rgb * clouds.a;

    fragColor = vec4(result, 1.0);
}
