#ifndef SIMPLE_TOON_INPUT_INCLUDED
#define SIMPLE_TOON_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

CBUFFER_START(UnityPerMaterial)
float4 _BaseColor;
float4 _ShadeColor;
float _BaseColor_Step;
float _StepSmoothness;
float _BumpScale;
float _Rim_Strength;
float4 _RimLightColor;
float4 _MatCapColor;

float4 _Outline_Color;
float _Outline_Width;
half _Cutoff;
float _USE_CHAR_SHADOW;

float4 _MainTex_ST;
float4 _BaseMap_ST;
float4 _NormalMap_ST;
float4 _ClippingMask_ST;
float4 _MatCapMap_ST;
CBUFFER_END

TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
TEXTURE2D(_NormalMap);
TEXTURE2D(_ClippingMask);
TEXTURE2D(_MatCapMap); SAMPLER(sampler_MatCapMap);

#endif