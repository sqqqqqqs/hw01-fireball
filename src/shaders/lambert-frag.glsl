#version 300 es

// This is a fragment shader. If you've opened this file first, please
// open and read lambert.vert.glsl before reading on.
// Unlike the vertex shader, the fragment shader actually does compute
// the shading of geometry. For every pixel in your program's output
// screen, the fragment shader is run for every bit of geometry that
// particular pixel overlaps. By implicitly interpolating the position
// data passed into the fragment shader by the vertex shader, the fragment shader
// can compute what color to apply to its pixel based on things like vertex
// position, light position, and vertex color.
precision highp float;

uniform vec4 u_Color; // The color with which to render this instance of geometry.
uniform float u_Time; // seconds since start
uniform vec3 u_CameraPos; // eye position, for the rim glow
uniform vec3 u_HotColor; // GUI slider: the "hottest" color in the palette

// These are the interpolated values out of the rasterizer, so you can't know
// their specific values without knowing the vertices that contributed to them
in vec4 fs_Nor;
in vec4 fs_LightVec;
in vec4 fs_Col;
in float fs_Height; // how much this point is displaced, makes tall spots hotter
in float fs_Detail;  // the fine noise, drives most of the color variety
in vec4 fs_Pos;      // for figuring out the view direction
in float fs_MouseGlow; // brightens wherever the mouse is touching

out vec4 out_Col; // This is the final output color that you will see on your
                  // screen for the pixel that is currently being processed.

const float PI = 3.14159265359;

// eases smoothly from ember to hot color, no weird hue shifts along the way
vec3 firePalette(float t) {
    float ease = (1.0 - cos(t * PI)) * 0.5;
    vec3 ember = vec3(0.12, 0.02, 0.0);
    return mix(ember, u_HotColor, ease);
}

void main()
{
        // Calculate the diffuse term for Lambert shading
        float diffuseTerm = dot(normalize(fs_Nor), normalize(fs_LightVec));
        // Avoid negative lighting values
        // diffuseTerm = clamp(diffuseTerm, 0, 1);

        float ambientTerm = 0.2;

        float lightIntensity = diffuseTerm + ambientTerm;   //Add a small float value to the color multiplier
                                                            //to simulate ambient lighting. This ensures that faces that are not
                                                            //lit by our point light are not completely black.
        // fire glows on its own, so don't let the dark side go fully black
        lightIntensity = clamp(lightIntensity, 0.45, 1.2);

        // noise detail picks the base color, height pushes tall spots hotter
        float t = clamp((fs_Detail - 0.5) * 1.8 + 0.5 + fs_Height * 1.0, 0.0, 1.0);
        float shimmer = 0.04 * sin(u_Time * 0.6 + fs_Detail * 4.0); // tiny color flicker over time
        vec3 fireColor = firePalette(clamp(t + shimmer, 0.0, 1.0));

        // rim glow: edges facing away from the camera catch extra light
        vec3 viewDir = normalize(u_CameraPos - fs_Pos.xyz);
        float fresnel = pow(1.0 - clamp(dot(normalize(fs_Nor.xyz), viewDir), 0.0, 1.0), 2.0);
        vec3 rimColor = vec3(1.0, 0.7, 0.3) * fresnel * 0.85;

        // extra glow right where the mouse is touching
        vec3 mouseGlow = u_HotColor * fs_MouseGlow * 2.5;

        out_Col = vec4(fireColor * lightIntensity + rimColor + mouseGlow, 1.0);
}
