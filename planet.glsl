const float PLANET_RADIUS = 1.0;
const float MAX_HEIGHT = 0.15;
const int MARCH_STEPS = 96;
const float MARCH_PRECISION = 0.001;
const vec3 atmColor = vec3(0.4, 0.6, 1.0);

// Improved noise function for better distribution
float hash(vec3 p) {
    p = fract(p * vec3(443.8975,397.2973, 491.1871));
    p += dot(p.zxy, p.yxz + 19.19);
    return fract(p.x * p.y * p.z);
}

// 3D noise for better spherical distribution
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

// Improved FBM using 3D coordinates
float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    
    // Rotation matrices for better feature distribution
    mat3 rot1 = mat3(
        cos(0.5), sin(0.5), 0,
        -sin(0.5), cos(0.5), 0,
        0, 0, 1
    );
    
    mat3 rot2 = mat3(
        cos(0.7), 0, sin(0.7),
        0, 1, 0,
        -sin(0.7), 0, cos(0.7)
    );
    
    for(int i = 0; i < 4; i++) {
        value += amplitude * noise(p * frequency);
        p = rot1 * rot2 * p;
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// Get height using 3D position directly
float getHeight(vec3 p) {
    vec3 n = normalize(p);
    
    // Use position directly for noise sampling
    float base = fbm(n * 3.0);
    
    // Add larger features with different frequency
    float large = fbm(n * 1.5) * 0.5;
    
    // Combine different scales
    return (base + large) * MAX_HEIGHT;
}

float getSurfaceDistance(vec3 p) {
    float d = length(p) - PLANET_RADIUS;
    float h = getHeight(p);
    return d - h;
}

vec4 marchSurface(vec3 ro, vec3 rd) {
    float t = 0.0;
    float h = 0.0;
    
    for(int i = 0; i < MARCH_STEPS; i++) {
        vec3 p = ro + rd * t;
        float d = getSurfaceDistance(p);
        
        if(d < MARCH_PRECISION) {
            h = getHeight(p);
            return vec4(p, h);
        }
        
        t += d * 0.5;
        
        if(t > 20.0) break;
    }
    
    return vec4(0, 0, 0, -1);
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

// Color based on position and height
vec3 getTerrainColor(vec3 pos, float height, vec3 normal) {
    // Base colors
    vec3 deepColor = vec3(0.1, 0.2, 0.0);
    vec3 lowColor = vec3(0.2, 0.35, 0.1);
    vec3 highColor = vec3(0.9, 0.9, 0.8);
    vec3 rockColor = vec3(0.5, 0.4, 0.3);
    
    // Height-based coloring
    vec3 baseColor = mix(
        lowColor,
        highColor,
        smoothstep(0.0, MAX_HEIGHT, height)
    );
    
    // Add deep valleys
    baseColor = mix(
        deepColor,
        baseColor,
        smoothstep(-MAX_HEIGHT * 0.5, 0.0, height)
    );
    
    // Add rock on steep slopes
    float slope = 1.0 - dot(normal, normalize(pos));
    return mix(baseColor, rockColor, smoothstep(0.2, 0.6, slope));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    
    // Camera setup
    float time = iTime * 0.2;
    float camDist = 4.0;
    float camHeight = 2.5;
    
    vec3 ro = vec3(
        camDist * cos(time),
        camHeight * sin(time * 0.5),
        camDist * sin(time)
    );
    vec3 ta = vec3(0.0);
    
    // Camera matrix
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
    vec3 vv = normalize(cross(uu, ww));
    vec3 rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);
    
    // Ray march the surface
    vec4 hit = marchSurface(ro, rd);
    vec3 col;
    
    if(hit.w >= 0.0) {
        vec3 pos = hit.xyz;
        vec3 normal = calcNormal(pos);
        float height = hit.w;
        
        // Lighting
        vec3 lightDir = normalize(vec3(1.0, 0.5, -0.5));
        float diff = max(dot(normal, lightDir), 0.0);
        float amb = 0.3;
        
        // Get surface color
        vec3 baseColor = getTerrainColor(pos, height, normal);
        
        // Apply lighting
        col = baseColor * (diff + amb);
        
        // Add atmosphere
        float fresnel = pow(1.0 - max(dot(-rd, normal), 0.0), 2.0);
        col += atmColor * fresnel * 0.4;
        
        // Add shadows
        float shadow = smoothstep(0.2, 0.8, diff);
        col *= mix(0.8, 1.0, shadow);
    } else {
        // Background
        float stars = pow(hash(rd), 20.0) * 0.5;
        col = vec3(0.02, 0.02, 0.04) + stars;
        
        // Add planet glow
        vec2 sphereUV = normalize(rd.xz);
        float dist = length(sphereUV);
        float glow = exp(-dist * 2.0) * 0.1;
        col += atmColor * glow;
    }
    
    // Tone mapping
    col = pow(col, vec3(0.4545));
    col = col / (1.0 + col);
    
    fragColor = vec4(col, 1.0);
}
