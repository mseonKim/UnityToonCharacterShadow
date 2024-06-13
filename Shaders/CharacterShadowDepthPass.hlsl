#ifndef CHARACTER_SHADOW_DEPTH_PASS_INCLUDED
#define CHARACTER_SHADOW_DEPTH_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "CharacterShadowTransforms.hlsl"

// Below material properties must be declared in seperate shader input to make compatible with SRP Batcher.
// CBUFFER_START(UnityPerMaterial)
//     float4 _ClippingMask_ST;
// CBUFFER_END
// TEXTURE2D(_ClippingMask);

SAMPLER(sampler_ClippingMask);

struct Attributes
{
    float4 position     : POSITION;
    float2 texcoord     : TEXCOORD0;
    float3 normal     : NORMAL;
    // UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float2 uv           : TEXCOORD0;
    float3 positionOS   : TEXCOORD1;
    float4 positionCS   : SV_POSITION;
    // UNITY_VERTEX_INPUT_INSTANCE_ID
    // UNITY_VERTEX_OUTPUT_STEREO
};

Varyings CharShadowVertex(Attributes input)
{
    Varyings output = (Varyings)0;
    // UNITY_SETUP_INSTANCE_ID(input);
    // UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    output.uv = TRANSFORM_TEX(input.texcoord, _ClippingMask);
    output.positionCS = CharShadowObjectToHClip(input.position.xyz, input.normal);

#if UNITY_REVERSED_Z
    output.positionCS.z = min(output.positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    output.positionCS.z = max(output.positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    output.positionCS.xy *= _CharShadowCascadeParams.y;

    output.positionOS = input.position.xyz;

    return output;
}

float CharShadowFragment(Varyings input) : SV_TARGET
{
    // UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    float alphaClipVar = SAMPLE_TEXTURE2D(_ClippingMask, sampler_ClippingMask, input.uv).r;
    clip(alphaClipVar- 0.001);
    
    return input.positionCS.z;
}
#endif
