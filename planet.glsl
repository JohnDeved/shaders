const float PLANET_RADIUS = 1.0;
const float MAX_HEIGHT = 0.15;
const float WATER_LEVEL = 0.05; // Increased from 0.02
const int MARCH_STEPS = 150; // Increased from 128
const float MARCH_PRECISION = 0.001;
const vec3 atmColor = vec3(0.4, 0.6, 1.0);
const vec3 waterShallowColor = vec3(0.1, 0.5, 0.8);    // Brighter shallow water
const vec3 waterColor = vec3(0.1, 0.35, 0.6);          // Mid-depth water
const vec3 waterDeepColor = vec3(0.02, 0.1, 0.3);      // Darker deep water
const vec3 beachColor = vec3(0.76, 0.7, 0.5);

// Add these constants near the top with other constants
const float MIN_ZOOM = 1.2;    // Closest distance allowed
const float MAX_ZOOM = 6.0;   // Furthest distance allowed
const float MAX_CAM_TILT = 0.5; // Maximum camera tilt factor (0.0 - 1.0)

// Add this with other constants at the top
const float BASE_FOV = 1.5;    // Original FOV multiplier
const float MIN_FOV = 0.8;     // Narrower FOV when zoomed in
const float MAX_FOV = 1.5;     // Wide FOV when zoomed out

// Grouped noise functions together
// Renamed hash() to rand3() for clarity
float rand3(vec3 p) {
    p = fract(p * vec3(443.8975));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y * p.z);
}

// Renamed noise() to noise3() for clarity
float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = rand3(i);
    float b = rand3(i + vec3(1,0,0));
    float c = rand3(i + vec3(0,1,0));
    float d = rand3(i + vec3(1,1,0));
    float e = rand3(i + vec3(0,0,1));
    float f1 = rand3(i + vec3(1,0,1));
    float g = rand3(i + vec3(0,1,1));
    float h = rand3(i + vec3(1,1,1));
    
    return mix(
        mix(mix(a,b,f.x), mix(c,d,f.x), f.y),
        mix(mix(e,f1,f.x), mix(g,h,f.x), f.y),
        f.z
    );
}

// Renamed ridgeNoise() to ridgeNoise3() for clarity
float ridgeNoise3(vec3 p) {
    float n = noise3(p);
    n = abs(n);
    n = 1.0 - n;
    return n * n * (3.0 - 2.0 * n) * 0.2; // Lower multiplier to soften
}

// Terrain utilities
// Slightly adjusted smoothing
float smoothTerrain(float h) {
    // Smooth transition between flat and varied terrain
    float flatness = smoothstep(0.2, 0.4, h) * (1.0 - smoothstep(0.6, 0.8, h));
    return mix(h, h * (1.0 - flatness * 0.5), 1.15);
}

float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.7;
    float frequency = 1.0;
    vec3 shift = vec3(100);
    // Increase loop count to 5 for more detail
    for(int i = 0; i < 5; i++) {
        float n = noise3(p * frequency);
        // Smooth terrain transitions
        n = smoothTerrain(n);
        value += amplitude * n;

        // Subtle injection of ridge noise
        float ridge = ridgeNoise3(p * frequency + vec3(100.0)) * amplitude * 0.25;
        value += ridge;

        frequency *= 1.8;
        amplitude *= 0.65;  // Gentler amplitude falloff
        shift = shift * 1.4;
    }
    
    return value * 0.8;
}

// Tweaked name for clarity
float computeTerrainHeight(vec3 pos) {
    return fbm(normalize(pos) * 3.0) * MAX_HEIGHT;
}

// ...existing code...
float computeWaterHeight(vec3 pos) {
    // Renamed time to globalTime
    float globalTime = iTime * 0.5;
    // Removed second wave call for performance
    float wave = sin(dot(pos, vec3(1.0)) * 20.0 + globalTime) * 0.5;
    return WATER_LEVEL + wave * 0.003;
}

// Renamed for clarity
float computeSurfaceDistance(vec3 pos) {
    float dist = length(pos);
    float terrain = dist - (PLANET_RADIUS + computeTerrainHeight(pos));
    float water = dist - (PLANET_RADIUS + WATER_LEVEL);
    
    // Use separate distances for water and terrain
    return (water < terrain) ? water : terrain;
}

// ...existing code...
vec3 computeNormal(vec3 pos) {
    float eps = 0.001;
    vec2 h = vec2(eps, 0);
    return normalize(vec3(
        computeSurfaceDistance(pos + h.xyy) - computeSurfaceDistance(pos - h.xyy),
        computeSurfaceDistance(pos + h.yxy) - computeSurfaceDistance(pos - h.yxy),
        computeSurfaceDistance(pos + h.yyx) - computeSurfaceDistance(pos - h.yyx)
    ));
}

// Color & shading
// Adjusted color palette intensities
vec3 computeTerrainColor(vec3 pos, float height, vec3 normal) {
    // Enhanced color palette
    vec3 deepColor = vec3(0.15, 0.25, 0.05);    // Darker green valleys
    vec3 lowColor = vec3(0.25, 0.35, 0.1);      // Forest green
    vec3 plainColor = vec3(0.35, 0.42, 0.15);   // Grass green
    vec3 highColor = vec3(0.45, 0.42, 0.25);    // Yellow-green hills
    vec3 peakColor = vec3(0.8);                 // Gray peaks
    vec3 steepColor = vec3(0.25);              // Dark gray for cliffs
    
    float heightFactor = height / MAX_HEIGHT;
    vec3 baseColor;
    
    // Beach zone
    float beachZone = 0.01; // Width of beach
    if (height < WATER_LEVEL + beachZone && height > WATER_LEVEL) {
        float beachBlend = smoothstep(WATER_LEVEL, WATER_LEVEL + beachZone, height);
        return mix(beachColor, lowColor, beachBlend);
    }
    
    // Rest of terrain coloring
    if (heightFactor > 0.75) {
        float blendFactor = smoothstep(0.75, 1.0, heightFactor);
        baseColor = mix(highColor, peakColor, blendFactor);
    } else if (heightFactor > 0.5) {
        // Hills (25%)
        float blendFactor = smoothstep(0.5, 0.75, heightFactor);
        baseColor = mix(plainColor, highColor, blendFactor);
    } else if (heightFactor > 0.2) {
        // Plains (30%)
        float blendFactor = smoothstep(0.2, 0.5, heightFactor);
        baseColor = mix(lowColor, plainColor, blendFactor);
    } else {
        // Valleys (20%)
        float blendFactor = smoothstep(0.0, 0.2, heightFactor);
        baseColor = mix(deepColor, lowColor, blendFactor);
    }
    
    // Handle steep areas with dark gray
    float slope = 1.0 - dot(normal, normalize(pos));
    float steepness = smoothstep(0.5, 0.7, slope);
    baseColor = mix(baseColor, steepColor, steepness);
    
    // Add subtle color variation
    vec3 colorVar = vec3(noise3(pos * 5.0) * 0.05);
    baseColor += colorVar;
    
    return baseColor;
}

// Slightly adjusted mixing factors in water color
vec3 computeWaterColor(vec3 p, vec3 normal, vec3 rd, vec3 lightDir, float terrain_height) {
    float fresnel = pow(1.0 - max(dot(-rd, normal), 0.0), 4.0);
    float wave = sin(dot(p, vec3(1.0, 0.0, 1.0)) * 50.0 + iTime) * 0.02;
    float depth = WATER_LEVEL - terrain_height;
    float normalizedDepth = smoothstep(0.0, 0.01, depth);
    vec3 c = mix(
        waterShallowColor,
        waterColor,
        smoothstep(0.0, 0.03, depth)
    );
    c = mix(c, waterDeepColor, smoothstep(0.03, 0.08, depth));
    c *= mix(1.0, 0.5, normalizedDepth);
    c = mix(c, vec3(1.0), fresnel * 0.3);
    c += wave * mix(0.1, 0.02, normalizedDepth);
    vec3 reflDir = reflect(-lightDir, normal);
    float spec = pow(max(dot(reflDir, -rd), 0.0), 32.0);
    c += vec3(spec) * mix(0.6, 0.2, normalizedDepth);
    return c;
}

// ...existing code...

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    
    float cameraTime = iTime * 0.2;
    
    // Start at maximum zoom by default
    float zoom = MAX_ZOOM;
    if (iMouse.z > 0.0) {  // If mouse button is pressed
        float mouseY = iMouse.y / iResolution.y;  // Normalize to 0-1
        zoom = mix(MAX_ZOOM, MIN_ZOOM, mouseY);   // Map Y position to zoom range
    }
    
    // Calculate tilt factor based on zoom
    float tiltFactor = smoothstep(MAX_ZOOM, MIN_ZOOM, zoom) * MAX_CAM_TILT; // Max 0.7 up-tilt
    
    // Apply zoom and tilt to camera position
    vec3 ro = vec3(
        zoom * cos(cameraTime),
        zoom * 0.5 * (1.0 - tiltFactor), // Reduce vertical component when close
        zoom * sin(cameraTime)
    );
    
    // Adjust look-at point based on tilt
    vec3 ta = vec3(0.0, tiltFactor * 2.0, 0.0); // Look up more when close
    
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
    vec3 vv = normalize(cross(uu, ww));
    
    // Adjust FOV based on zoom level
    float fov = mix(MIN_FOV, MAX_FOV, smoothstep(MIN_ZOOM, MAX_ZOOM, zoom));
    vec3 rd = normalize(uv.x * uu + uv.y * vv + fov * ww);
    
    vec3 col = vec3(0.02, 0.02, 0.04);
    float t = 0.0;
    
    for(int stepIndex = 0; stepIndex < MARCH_STEPS; stepIndex++) {
        vec3 p = ro + rd * t;
        float d = computeSurfaceDistance(p);
        
        if(d < MARCH_PRECISION) {
            vec3 normal = computeNormal(p);
            float dist = length(p);
            float terrainHeight = computeTerrainHeight(p);
            float surface_height = dist - PLANET_RADIUS;
            
            vec3 lightDir = normalize(vec3(1.0, 0.5, -0.5));
            float diff = max(dot(normal, lightDir), 0.0);
            
            vec3 baseColor;
            // Explicitly check if we hit water surface
            if (surface_height < WATER_LEVEL + 0.001) {
                baseColor = computeWaterColor(p, normal, rd, lightDir, terrainHeight);
            } else {
                baseColor = computeTerrainColor(p, terrainHeight, normal);
            }
            
            col = baseColor * (diff + 0.3);
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
