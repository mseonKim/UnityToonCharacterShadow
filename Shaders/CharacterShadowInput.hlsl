#ifndef CHARACTER_SHADOW_INPUT_INCLUDED
#define CHARACTER_SHADOW_INPUT_INCLUDED

CBUFFER_START(CharShadow)
    float4 _CharShadowParams;
    float4x4 _CharShadowViewM;
    float4x4 _CharShadowProjM;
    float4 _CharShadowOffset0;
    float4 _CharShadowOffset1;
    float4 _CharShadowmapSize;              // rcp(width), rcp(height), width, height
    float4 _CharTransparentShadowmapSize;   // rcp(width), rcp(height), width, height
    float4 _CharShadowCascadeParams;        // x: cascadeMaxDistance, y: cascadeResolutionScale
    float4 _BrightestLightDirection;
    uint _CharShadowLocalLightIndex;
    uint _UseBrightestLight;
    uint _char_shadow_pad00_;
    uint _char_shadow_pad01_;
CBUFFER_END

#define _CharShadowBias                     _CharShadowParams.xy
#define _CharShadowStepSmoothness           _CharShadowParams.z
#define _HighSoftShadowBlurDistance         _CharShadowParams.w

TEXTURE2D(_CharShadowMap);
SAMPLER(sampler_CharShadowMap);
TEXTURE2D(_TransparentShadowMap);
TEXTURE2D(_TransparentAlphaSum);

#endif