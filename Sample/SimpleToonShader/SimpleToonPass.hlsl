#ifndef SIMPLE_TOON_PASS_INCLUDED
#define SIMPLE_TOON_PASS_INCLUDED

#include "Packages/com.unity.tooncharactershadow/Shaders/DeclareCharacterShadowTexture.hlsl"

struct VertexInput
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float2 texcoord0 : TEXCOORD0;
    float2 staticLightmapUV : TEXCOORD1;
    float2 dynamicLightmapUV : TEXCOORD2;
};

struct VertexOutput
{
    float4 pos : SV_POSITION;
    float2 uv0 : TEXCOORD0;
    float3 posWorld : TEXCOORD1;
    float3 normalWS : TEXCOORD2;
    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 3);
#ifdef DYNAMICLIGHTMAP_ON
    float2  dynamicLightmapUV   : TEXCOORD4; // Dynamic lightmap UVs
#endif
};

half LinearStep(half minValue, half maxValue, half In)
{
    return saturate((In-minValue) / (maxValue-minValue));
}

VertexOutput vert(VertexInput v)
{
    VertexOutput o = (VertexOutput)0;
    // UNITY_TRANSFER_INSTANCE_ID(v, o);
    // UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    o.pos = TransformObjectToHClip(v.vertex.xyz);
    o.uv0 = v.texcoord0;
    o.normalWS = TransformObjectToWorldDir(v.normal);
    o.posWorld = TransformObjectToWorld(v.vertex.xyz);
    return o;
}

half GetCharMainShadow(float3 worldPos, float opacity)
{
    return SampleCharacterAndTransparentShadow(worldPos, opacity);
}
half GetCharAdditionalShadow(float3 worldPos, float opacity, uint lightIndex)
{
    return SampleAdditionalCharacterAndTransparentShadow(worldPos, opacity, lightIndex);
}

float4 frag(VertexOutput i, half facing : VFACE) : SV_TARGET
{
    half alpha = 0;
    BRDFData brdfData;
    InitializeBRDFData(_BaseColor.rgb, 0, 0, 1, alpha, brdfData);
    
    float4 _BaseMap_var = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, TRANSFORM_TEX(i.uv0, _MainTex));
    float3 color = _BaseMap_var.rgb;
    float opacity = _BaseMap_var.a * _BaseColor.a;

    i.normalWS = normalize(i.normalWS);
    float4 _NormalMap_var = SAMPLE_TEXTURE2D(_NormalMap, sampler_MainTex, TRANSFORM_TEX(i.uv0, _NormalMap));
    float3 normalWS = lerp(i.normalWS, _NormalMap_var.rgb, _BumpScale);
    float2 normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.pos);


    Light mainLight = GetMainLight();
    half3 mainLightColor = mainLight.color * (mainLight.distanceAttenuation * mainLight.shadowAttenuation);

    // Half Lambert
    float M = _BaseColor_Step + _StepSmoothness;
    float m = _BaseColor_Step - _StepSmoothness;
    float3 baseColor = lerp(_ShadeColor.rgb, _BaseColor.rgb, LinearStep(m, M, dot(mainLight.direction, normalWS) * 0.5 + 0.5));

    half ssShadowAtten = 0;
    if (_USE_CHAR_SHADOW > 0)
    {
        ssShadowAtten = GetCharMainShadow(i.posWorld, opacity);
        baseColor = lerp(baseColor, _ShadeColor.rgb, ssShadowAtten);
    }

    color *= baseColor * mainLightColor;

#if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();
    half3 additionalLightsColor = 0;

    // Directional Lights
#if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK

        Light light = GetAdditionalLight(lightIndex, i.posWorld, 0);

    #ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
    #endif
        {
            half halfLambert = dot(light.direction, normalWS) * 0.5 + 0.5;
            half3 lightColor = light.color.rgb * light.distanceAttenuation * light.shadowAttenuation;
            half3 finalBaseColor = lerp(_ShadeColor.rgb, _BaseColor.rgb, LinearStep(m, M, halfLambert));
            if (_USE_CHAR_SHADOW > 0)
            {
                ssShadowAtten = GetCharAdditionalShadow(i.posWorld, opacity, lightIndex);
                finalBaseColor = lerp(baseColor, _ShadeColor.rgb, ssShadowAtten);
            }
            additionalLightsColor += _BaseMap_var.rgb * lightColor * finalBaseColor;
        }
    }
#endif

    // Local Lights
    InputData inputData = (InputData)0;
    inputData.positionWS = i.posWorld;
    inputData.normalizedScreenSpaceUV = normalizedScreenSpaceUV;
    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData.positionWS, 0);

    #ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
    #endif
        {
            half halfLambert = dot(light.direction, normalWS) * 0.5 + 0.5;
            half3 lightColor = light.color.rgb * light.distanceAttenuation * light.shadowAttenuation;
            half3 finalBaseColor = lerp(_ShadeColor.rgb, _BaseColor.rgb, LinearStep(m, M, halfLambert));
            if (_USE_CHAR_SHADOW > 0)
            {
                ssShadowAtten = GetCharAdditionalShadow(i.posWorld, opacity, lightIndex);
                finalBaseColor = lerp(baseColor, _ShadeColor.rgb, ssShadowAtten);
            }
            additionalLightsColor += _BaseMap_var.rgb * lightColor * finalBaseColor;
        }
    LIGHT_LOOP_END

    color += additionalLightsColor;
#endif

    // Rim Light
    float3 viewDir = normalize(_WorldSpaceCameraPos - i.posWorld).xyz;
    half emission = LinearStep(0.25, 0.75, pow(1 - saturate(dot(viewDir, normalWS)), _Rim_Strength));
    half3 rimColor = (_RimLightColor * emission).rgb;
    if (facing < 0.1)
    {
        rimColor = 0;
    }
    color += rimColor;
    
    // Matcap
    float3 viewNormal = TransformWorldToViewDir(normalWS);
    float2 matcapUV = viewNormal.xy * 0.5 + 0.5;
    float3 _MatCap_Sampler_var = SAMPLE_TEXTURE2D(_MatCapMap, sampler_MatCapMap, TRANSFORM_TEX(matcapUV, _MatCapMap)).rgb;
    color += _MatCap_Sampler_var * _MatCapColor.rgb;

    // GI
    #if defined(DYNAMICLIGHTMAP_ON)
        float3 bakedGI = SAMPLE_GI(i.staticLightmapUV, i.dynamicLightmapUV, i.vertexSH, normalWS);
    #else
        float3 bakedGI = SAMPLE_GI(i.staticLightmapUV, i.vertexSH, normalWS);
    #endif
    MixRealtimeAndBakedGI(mainLight, normalWS, bakedGI);
    float3 giColor = GlobalIllumination(brdfData, brdfData, 0, bakedGI, 0, i.posWorld, normalWS, viewDir, normalizedScreenSpaceUV);
    color += giColor;

    float4 finalColor = float4(color, opacity);
    return finalColor;
}

#endif