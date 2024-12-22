const float PLANET_RADIUS = 1.0;
const float MAX_HEIGHT = 0.15;
const int MARCH_STEPS = 64*4;
const float MARCH_PRECISION = 0.001;
const vec3 atmColor = vec3(0.4, 0.6, 1.0);

float hash(vec3 p) {
    p = fract(p * vec3(443.8975));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y * p.z);
}

float noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + vec3(1,0,0));
    float c = hash(i + vec3(0,1,0));
    float d = hash(i + vec3(1,1,0));
    float e = hash(i + vec3(0,0,1));
    float f1 = hash(i + vec3(1,0,1));
    float g = hash(i + vec3(0,1,1));
    float h = hash(i + vec3(1,1,1));
    
    return mix(
        mix(mix(a,b,f.x), mix(c,d,f.x), f.y),
        mix(mix(e,f1,f.x), mix(g,h,f.x), f.y),
        f.z
    );
}

// Domain warping function
vec3 warp(vec3 p) {
    vec3 q = vec3(
        noise(p + vec3(1.7)),
        noise(p + vec3(2.3)),
        noise(p + vec3(3.1))
    );
    return p + q * 0.7;
}

// Ridge noise for mountains
float ridge(float h) {
    h = abs(h);    // create creases
    h = 1.0 - h;   // invert so creases become ridges
    h = h * h;     // sharpen ridges
    return h;
}

float ridgeNoise(vec3 p) {
    float n = noise(p);
    n = abs(n);
    n = 1.0 - n;
    // Soften the ridge effect
    return n * n * (5.0 - 2.0 * n);
}

float erosion(vec3 p) {
    float e = noise(p * 4.0) * 0.5 + 0.5;  // Reduced frequency
    return pow(e, 1.2);  // Softer erosion
}

float smoothTerrain(float h) {
    // Smooth transition between flat and varied terrain
    float flatness = smoothstep(0.2, 0.4, h) * (1.0 - smoothstep(0.6, 0.8, h));
    return mix(h, h * (1.0 - flatness * 0.5), 1.0);
}

float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.7;
    float frequency = 1.0;
    vec3 shift = vec3(100);
    
    for(int i = 0; i < 4; i++) {
        float n = noise(p * frequency);
        
        // Smooth terrain transitions
        n = smoothTerrain(n);
        value += amplitude * n;
        
        // Gentle ridges for higher areas
        float ridge = amplitude * ridgeNoise(p * frequency + shift) * 0.25;
        ridge *= smoothstep(0.4, 0.7, value);
        value += ridge;
        
        // Subtle erosion
        value *= mix(1.0, erosion(p * frequency), 0.03);
        
        frequency *= 1.8;
        amplitude *= 0.65;  // Gentler amplitude falloff
        shift = shift * 1.4;
    }
    
    return value * 0.8;
}

float getHeight(vec3 p) {
    return fbm(normalize(p) * 3.0) * MAX_HEIGHT;
}

float getSurfaceDistance(vec3 p) {
    return length(p) - (PLANET_RADIUS + getHeight(p));
}

vec3 calcNormal(vec3 p) {
    float eps = 0.001;
    vec2 h = vec2(eps, 0);
    return normalize(vec3(
        getSurfaceDistance(p + h.xyy) - getSurfaceDistance(p - h.xyy),
        getSurfaceDistance(p + h.yxy) - getSurfaceDistance(p - h.yxy),
        getSurfaceDistance(p + h.yyx) - getSurfaceDistance(p - h.yyx)
    ));
}

vec3 getTerrainColor(vec3 pos, float height, vec3 normal) {
    // Enhanced color palette
    vec3 deepColor = vec3(0.15, 0.25, 0.05);    // Darker green valleys
    vec3 lowColor = vec3(0.25, 0.35, 0.1);      // Forest green
    vec3 plainColor = vec3(0.35, 0.42, 0.15);   // Grass green
    vec3 highColor = vec3(0.45, 0.42, 0.25);    // Yellow-green hills
    vec3 peakColor = vec3(0.8);                 // Gray peaks
    vec3 steepColor = vec3(0.25);              // Dark gray for cliffs
    
    float heightFactor = height / MAX_HEIGHT;
    vec3 baseColor;
    
    if (heightFactor > 0.75) {
        // Mountain peaks (top 25%)
        float t = smoothstep(0.75, 1.0, heightFactor);
        baseColor = mix(highColor, peakColor, t);
    } else if (heightFactor > 0.5) {
        // Hills (25%)
        float t = smoothstep(0.5, 0.75, heightFactor);
        baseColor = mix(plainColor, highColor, t);
    } else if (heightFactor > 0.2) {
        // Plains (30%)
        float t = smoothstep(0.2, 0.5, heightFactor);
        baseColor = mix(lowColor, plainColor, t);
    } else {
        // Valleys (20%)
        float t = smoothstep(0.0, 0.2, heightFactor);
        baseColor = mix(deepColor, lowColor, t);
    }
    
    // Handle steep areas with dark gray
    float slope = 1.0 - dot(normal, normalize(pos));
    float steepness = smoothstep(0.5, 0.7, slope);
    baseColor = mix(baseColor, steepColor, steepness);
    
    // Add subtle color variation
    vec3 colorVar = vec3(noise(pos * 5.0) * 0.05);
    baseColor += colorVar;
    
    return baseColor;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    
    float time = iTime * 0.2;
    vec3 ro = vec3(4.0 * cos(time), 2.0, 4.0 * sin(time));
    vec3 ta = vec3(0.0);
    
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
    vec3 vv = normalize(cross(uu, ww));
    vec3 rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);
    
    vec3 col = vec3(0.02, 0.02, 0.04);
    float t = 0.0;
    
    for(int i = 0; i < MARCH_STEPS; i++) {
        vec3 p = ro + rd * t;
        float d = getSurfaceDistance(p);
        
        if(d < MARCH_PRECISION) {
            vec3 normal = calcNormal(p);
            float height = getHeight(p);
            
            vec3 lightDir = normalize(vec3(1.0, 0.5, -0.5));
            float diff = max(dot(normal, lightDir), 0.0);
            
            col = getTerrainColor(p, height, normal) * (diff + 0.3);
            col += atmColor * pow(1.0 - max(dot(-rd, normal), 0.0), 2.0) * 0.4;
            break;
        }
        
        t += d * 0.5;
        if(t > 20.0) break;
    }
    
    // Simple atmospheric glow
    col += atmColor * exp(-length(uv) * 2.0) * 0.1;
    
    // Basic tone mapping
    col = col / (1.0 + col);
    
    fragColor = vec4(col, 1.0);
}
