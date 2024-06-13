#ifndef CHARACTER_SHADOW_DEPTH_INPUT_INCLUDED
#define CHARACTER_SHADOW_DEPTH_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Shadow/ShadowSamplingTent.hlsl"
#include "./CharacterShadowTransforms.hlsl"

#define MAX_CHAR_SHADOWMAPS 1

half GetLinearStep(float m, float M, float x)
{
    return saturate((x - m) / (M - m));
}

uint LocalLightIndexToShadowmapIndex(uint lightindex)
{
    if (_UseBrightestLight > 0 && lightindex == _CharShadowLocalLightIndex)
        return 0;

    return MAX_CHAR_SHADOWMAPS;
}

#define ADDITIONAL_CHARSHADOW_CHECK(i, lightIndex) { \
        i = LocalLightIndexToShadowmapIndex(lightIndex); \
        if (i >= MAX_CHAR_SHADOWMAPS) \
            return 0; }

float3 TransformWorldToCharShadowCoord(float3 worldPos)
{
    float4 clipPos = CharShadowWorldToHClip(worldPos);
#if UNITY_REVERSED_Z
    clipPos.z = min(clipPos.z, UNITY_NEAR_CLIP_VALUE);
#else
    clipPos.z = max(clipPos.z, UNITY_NEAR_CLIP_VALUE);
#endif
    float3 ndc = clipPos.xyz / clipPos.w;
    float2 ssUV = ndc.xy * 0.5 + 0.5;
#if UNITY_UV_STARTS_AT_TOP
    ssUV.y = 1.0 - ssUV.y;
#endif
    return float3(ssUV, ndc.z);
}

void ScaleUVForCascadeCharShadow(inout float2 uv)
{
    // Refactor below logic to MAD
    // uv *= _CharShadowCascadeParams.y;
    // uv = (1.0 - _CharShadowCascadeParams.y) * 0.5 + uv;
    uv = uv * _CharShadowCascadeParams.y - (_CharShadowCascadeParams.y * 0.5 + 0.5);
}

// Reference: UE5 SpiralBlur-Texture
half SampleSpiralBlur(TEXTURE2D_PARAM(tex, samplerTex), float2 UV, float Distance, float DistanceSteps = 16, float RadialSteps = 8, float RadialOffset = 0.62, float KernelPower = 1)
{
    half CurColor = 0;
    float2 NewUV = UV;
    int i = 0;
    float StepSize = Distance / (int)DistanceSteps;
    float CurDistance = 0;
    float2 CurOffset = 0;
    float SubOffset = 0;
    float accumdist = 0;

    if (DistanceSteps < 1)
    {
        return SAMPLE_TEXTURE2D(tex, samplerTex, UV).r;		
    }

    while (i < (int)DistanceSteps)
    {
        CurDistance += StepSize;
        for (int j = 0; j < (int)RadialSteps; j++)
        {
            SubOffset +=1;
            CurOffset.x = cos(TWO_PI * (SubOffset / RadialSteps));
            CurOffset.y = sin(TWO_PI * (SubOffset / RadialSteps));
            NewUV.x = UV.x + CurOffset.x * CurDistance;
            NewUV.y = UV.y + CurOffset.y * CurDistance;
            float distpow = pow(CurDistance, KernelPower);
            CurColor += SAMPLE_TEXTURE2D(tex, samplerTex, NewUV).r * distpow;		
            accumdist += distpow;
        }
        SubOffset += RadialOffset;
        i++;
    }
    CurColor = CurColor;
    CurColor /= accumdist;
    return CurColor;
}

half SampleCharacterShadowmap(float2 uv, float z)
{
    // UV must be the scaled value with ScaleUVForCascadeCharShadow()
    float var = SAMPLE_TEXTURE2D(_CharShadowMap, sampler_CharShadowMap, uv).r;
    return (var - z) > _CharShadowBias.x;
}

half SampleCharacterShadowmapFiltered(float2 uv, float z, float biasOffset)
{
    // UV must be the scaled value with ScaleUVForCascadeCharShadow()
    z += 0.00001;
#ifdef _HIGH_CHAR_SOFTSHADOW
    float distance = _CharShadowmapSize.x * _CharShadowCascadeParams.y * _HighSoftShadowBlurDistance;
    float attenuation = SampleSpiralBlur(_CharShadowMap, sampler_CharShadowMap, uv, distance);
#else
    float ow = _CharShadowmapSize.x * _CharShadowCascadeParams.y;
    float oh = _CharShadowmapSize.y * _CharShadowCascadeParams.y;
    float attenuation = SAMPLE_TEXTURE2D(_CharShadowMap, sampler_CharShadowMap, uv).r
                        + SAMPLE_TEXTURE2D(_CharShadowMap, sampler_CharShadowMap, uv + float2(ow, ow)).r
                        + SAMPLE_TEXTURE2D(_CharShadowMap, sampler_CharShadowMap, uv + float2(ow, -ow)).r
                        + SAMPLE_TEXTURE2D(_CharShadowMap, sampler_CharShadowMap, uv + float2(-ow, ow)).r
                        + SAMPLE_TEXTURE2D(_CharShadowMap, sampler_CharShadowMap, uv + float2(-ow, -ow)).r;
    attenuation /= 5.0f;
#endif

    float smoothness = _CharShadowStepSmoothness;
    return GetLinearStep(-smoothness, smoothness, (attenuation - z) - (_CharShadowBias.x + biasOffset)); // (attenuation - z) > _CharShadowBias.x;
}


half SampleTransparentShadowmap(float2 uv, float z, SamplerState s)
{
    // UV must be the scaled value with ScaleUVForCascadeCharShadow()
    float var = SAMPLE_TEXTURE2D(_TransparentShadowMap, s, uv).r;
    return (var - z) > _CharShadowBias.x;
}

half SampleTransparentShadowmapFiltered(float2 uv, float z, SamplerState s)
{
    // UV must be the scaled value with ScaleUVForCascadeCharShadow()
    z += 0.00001;
#if _HIGH_CHAR_SOFTSHADOW
    float distance = _CharTransparentShadowmapSize.x * _CharShadowCascadeParams.y * _HighSoftShadowBlurDistance;
    float attenuation = SampleSpiralBlur(_TransparentShadowMap, s, uv, distance);
#else
    float ow = _CharTransparentShadowmapSize.x * _CharShadowCascadeParams.y;
    float oh = _CharTransparentShadowmapSize.y * _CharShadowCascadeParams.y;
    float attenuation = SAMPLE_TEXTURE2D(_TransparentShadowMap, s, uv).r
                        + SAMPLE_TEXTURE2D(_TransparentShadowMap, s, uv + float2(ow, ow)).r
                        + SAMPLE_TEXTURE2D(_TransparentShadowMap, s, uv + float2(ow, -ow)).r
                        + SAMPLE_TEXTURE2D(_TransparentShadowMap, s, uv + float2(-ow, ow)).r
                        + SAMPLE_TEXTURE2D(_TransparentShadowMap, s, uv + float2(-ow, -ow)).r;
    attenuation /= 5.0f;
#endif

    float smoothness = _CharShadowStepSmoothness;
    return GetLinearStep(-smoothness, smoothness, (attenuation - z) - _CharShadowBias.x);
}

half TransparentAttenuation(float2 uv, float opacity)
{
    // UV must be the scaled value with ScaleUVForCascadeCharShadow()
    // Saturate since texture could have value more than 1
    return saturate(SAMPLE_TEXTURE2D(_TransparentAlphaSum, sampler_CharShadowMap, uv).r - opacity);    // Total alpha sum - current pixel's alpha
}

half GetTransparentShadow(float2 uv, float z, float opacity)
{
    // UV must be the scaled value with ScaleUVForCascadeCharShadow()
    half hidden = SampleTransparentShadowmapFiltered(uv, z, sampler_CharShadowMap);
    half atten = TransparentAttenuation(uv, opacity);
    return min(hidden, atten);
}

half CharacterAndTransparentShadowmap(float2 uv, float z, float opacity, float biasOffset = 0)
{
    // Scale uv first for cascade char shadow map
    ScaleUVForCascadeCharShadow(uv);
    return max(SampleCharacterShadowmapFiltered(uv, z, biasOffset), GetTransparentShadow(uv, z, opacity));
}

half SampleCharacterAndTransparentShadow(float3 worldPos, float opacity, float biasOffset = 0)
{
    if (dot(_MainLightPosition.xyz, _BrightestLightDirection.xyz) < 0.9999)
        return 0;

    if (IfCharShadowCulled(TransformWorldToView(worldPos).z))
        return 0;

    float3 coord = TransformWorldToCharShadowCoord(worldPos);
    return CharacterAndTransparentShadowmap(coord.xy, coord.z, opacity, biasOffset);
}

half SampleAdditionalCharacterAndTransparentShadow(float3 worldPos, float opacity, uint lightIndex = 0, float biasOffset = 0)
{
#ifndef USE_FORWARD_PLUS
    return 0;
#endif
    uint i;
    ADDITIONAL_CHARSHADOW_CHECK(i, lightIndex)

    if (IfCharShadowCulled(TransformWorldToView(worldPos).z))
        return 0;

    float3 coord = TransformWorldToCharShadowCoord(worldPos);
    return CharacterAndTransparentShadowmap(coord.xy, coord.z, opacity, biasOffset);
}

#endif