#ifndef CHARACTER_SHADOW_TRANSFORMS_INCLUDED
#define CHARACTER_SHADOW_TRANSFORMS_INCLUDED

#include "./CharacterShadowInput.hlsl"

#define _CharShadowCullingDist -(_CharShadowCascadeParams.x - 2) // should be less than renderer feature's max cascade split value 

float3 ApplyCharShadowBias(float3 positionWS, float3 normalWS, float3 lightDirection)
{
    float depthBias = _CharShadowBias.x;
    float normalBias = _CharShadowBias.y;

    // Depth Bias
    positionWS = lightDirection * depthBias + positionWS;

    // Normal Bias
    float invNdotL = 1.0 - saturate(dot(lightDirection, normalWS));
    float scale = invNdotL * -normalBias;
    positionWS = normalWS * scale.xxx + positionWS;
    return positionWS;
}

float4 CharShadowWorldToView(float3 positionWS)
{
    return mul(_CharShadowViewM, float4(positionWS, 1.0));
}
float4 CharShadowViewToHClip(float4 positionVS)
{
    return mul(_CharShadowProjM, positionVS);
}
float4 CharShadowWorldToHClip(float3 positionWS)
{
    return CharShadowViewToHClip(CharShadowWorldToView(positionWS));
}
float4 CharShadowObjectToHClip(float3 positionOS, float3 normalWS)
{
    float3 positionWS = mul(UNITY_MATRIX_M, float4(positionOS, 1.0)).xyz;
    positionWS = ApplyCharShadowBias(positionWS, normalWS, _BrightestLightDirection.xyz);

    return CharShadowWorldToHClip(positionWS);
}
float4 CharShadowObjectToHClipWithoutBias(float3 positionOS)
{
    float3 positionWS = mul(UNITY_MATRIX_M, float4(positionOS, 1.0)).xyz;
    return CharShadowWorldToHClip(positionWS);
}

// Skip if too far (since we don't use mipmap for charshadowmap, manually cull this calculation based on view depth.)
bool IfCharShadowCulled(float viewPosZ)
{
    return viewPosZ < _CharShadowCullingDist;
}

#endif