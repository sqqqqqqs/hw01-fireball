#version 300 es

//This is a vertex shader. While it is called a "shader" due to outdated conventions, this file
//is used to apply matrix transformations to the arrays of vertex data passed to it.
//Since this code is run on your GPU, each vertex is transformed simultaneously.
//If it were run on your CPU, each vertex would have to be processed in a FOR loop, one at a time.
//This simultaneous transformation allows your program to run much faster, especially when rendering
//geometry with millions of vertices.

uniform mat4 u_Model;       // The matrix that defines the transformation of the
                            // object we're rendering. In this assignment,
                            // this will be the result of traversing your scene graph.

uniform mat4 u_ModelInvTr;  // The inverse transpose of the model matrix.
                            // This allows us to transform the object's normals properly
                            // if the object has been non-uniformly scaled.

uniform mat4 u_ViewProj;    // The matrix that defines the camera's transformation.
                            // We've written a static matrix for you to use for HW2,
                            // but in HW3 you'll have to generate one yourself

uniform float u_Time;       // seconds since start, for animation

uniform vec4 u_Mouse;       // xyz = where the mouse hit, w = 1 if held else 0

uniform float u_DisplacementScale; // GUI slider: how strong the bumps are
uniform float u_NoiseScale;        // GUI slider: how fine-grained the detail noise is
uniform float u_MouseStrength;     // GUI slider: how much the mouse bulge pushes out

in vec4 vs_Pos;             // The array of vertex positions passed to the shader

in vec4 vs_Nor;             // The array of vertex normals passed to the shader

in vec4 vs_Col;             // The array of vertex colors passed to the shader.

out vec4 fs_Nor;            // The array of normals that has been transformed by u_ModelInvTr. This is implicitly passed to the fragment shader.
out vec4 fs_LightVec;       // The direction in which our virtual light lies, relative to each vertex. This is implicitly passed to the fragment shader.
out vec4 fs_Col;            // The color of each vertex. This is implicitly passed to the fragment shader.
out float fs_Height;        // total displacement here, feeds the fire color
out float fs_Detail;        // just the fine fBm noise, spread evenly everywhere
out vec4 fs_Pos;            // world-ish pos, for the fresnel glow later
out float fs_MouseGlow;     // how much the mouse bulge pushed this vertex

const vec4 lightPos = vec4(5, 5, 3, 1); //The position of our virtual light, which is used to compute the shading of
                                        //the geometry in the fragment shader.

// ---------- Noise ----------
// just a hash: turns a 3D point into a pseudo-random float
float hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

// smooth noise: blend the hash values at the 8 corners around p
float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // smooth the blend so it's not linear

    float n000 = hash3(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash3(i + vec3(1.0, 1.0, 1.0));

    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);

    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);

    return mix(nxy0, nxy1, f.z);
}

// fBm: stack up several octaves of noise, each finer and weaker than the last
float fbm(vec3 p, int octaves, float lacunarity, float gainAmt) {
    float sum = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 8; ++i) {
        if (i >= octaves) break;
        sum += amp * noise3(p * freq);
        freq *= lacunarity;
        amp *= gainAmt;
    }
    return sum;
}

// ---------- Toolbox Functions ----------
// bias: nudges t toward 0 or 1 depending on b
float bias(float b, float t) {
    return pow(t, log(b) / log(0.5));
}

// gain: like bias but squeezes/stretches around the middle instead of the ends
float gain(float g, float t) {
    if (t < 0.5) return bias(1.0 - g, 2.0 * t) * 0.5;
    return 1.0 - bias(1.0 - g, 2.0 - 2.0 * t) * 0.5;
}

// triangle wave: linear oscillation between 0 and 0.5*amplitude, period = amplitude/freq
float triangleWave(float x, float freq, float amplitude) {
    return abs(mod(x * freq, amplitude) - 0.5 * amplitude);
}

// smooth bump centered at c, fading out over width w
float pulse(float c, float w, float x) {
    float t = abs(x - c);
    if (t > w) return 0.0;
    t /= w;
    return 1.0 - t * t * (3.0 - 2.0 * t);
}

void main()
{
    fs_Col = vs_Col;                         // Pass the vertex colors to the fragment shader for interpolation

    mat3 invTranspose = mat3(u_ModelInvTr);
    fs_Nor = vec4(invTranspose * vec3(vs_Nor), 0);          // Pass the vertex normals to the fragment shader for interpolation.
                                                            // Transform the geometry's normals by the inverse transpose of the
                                                            // model matrix. This is necessary to ensure the normals remain
                                                            // perpendicular to the surface after the surface is transformed by
                                                            // the model matrix.


    vec3 objPos = vs_Pos.xyz;
    vec3 objNor = normalize(vs_Nor.xyz);

    // warp the position with coarse noise first, so the sphere roils unevenly instead of breathing in sync
    vec3 warp = vec3(
        noise3(objPos * 0.8 + u_Time * 0.15),
        noise3(objPos * 0.8 + vec3(5.2, 1.3, 7.1) + u_Time * 0.15),
        noise3(objPos * 0.8 + vec3(2.1, 9.4, 3.3) + u_Time * 0.15)
    );
    vec3 warpedPos = objPos + (warp - 0.5) * 0.6;

    // the big low-freq bumps: a few sine waves plus a triangle wave for texture
    float lowFreq = sin(warpedPos.x * 1.5 + u_Time * 0.6)
                  + sin(warpedPos.y * 1.7 - u_Time * 0.4)
                  + sin(warpedPos.z * 1.3 + u_Time * 0.5);
    lowFreq /= 3.0;
    float triWobble = triangleWave(u_Time * 0.05 + objPos.x * 0.1, 1.0, 1.0) * 2.0 - 0.5;

    float baseAmp = 0.34;
    float baseHeight = (lowFreq * 0.7 + triWobble * 0.3) * baseAmp;

    // finer fBm detail on top -- capped at 4 octaves so it doesn't alias on a normal-res mesh
    float detail = fbm(warpedPos * 2.0 * u_NoiseScale + u_Time * 0.3, 4, 2.0, 0.5);
    float shapedDetail = gain(0.6, detail); // roughly 0-1, reshaped for more contrast

    // little raised veins wherever the detail noise sits near 0.5
    float vein = pulse(0.5, 0.08, shapedDetail);
    float detailHeight = (shapedDetail - 0.5) * 0.18 + vein * 0.025;

    float height = (baseHeight + detailHeight) * u_DisplacementScale;

    vec3 displacedObjPos = objPos + objNor * height;
    vec4 modelposition = u_Model * vec4(displacedObjPos, 1.0);

    // bulge toward the mouse while it's held down
    float mouseBulge = 0.0;
    if (u_Mouse.w > 0.5) {
        float d = distance(modelposition.xyz, u_Mouse.xyz);
        mouseBulge = 0.35 * u_MouseStrength * smoothstep(1.0, 0.0, d);
        modelposition.xyz += normalize(fs_Nor.xyz) * mouseBulge;
    }

    fs_Height = height + mouseBulge;
    fs_Detail = shapedDetail;
    fs_Pos = modelposition;
    fs_MouseGlow = mouseBulge;

    fs_LightVec = lightPos - modelposition;  // Compute the direction in which the light source lies

    gl_Position = u_ViewProj * modelposition;// gl_Position is a built-in variable of OpenGL which is
                                             // used to render the final positions of the geometry's vertices
}
