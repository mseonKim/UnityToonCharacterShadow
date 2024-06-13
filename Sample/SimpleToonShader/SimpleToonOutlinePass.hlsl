#ifndef SIMPLE_TOON_OUTLINE_PASS_INCLUDED
#define SIMPLE_TOON_OUTLINE_PASS_INCLUDED

struct VertexInput
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float2 texcoord0 : TEXCOORD0;

};
struct VertexOutput
{
    float4 pos : SV_POSITION;
};

VertexOutput vert (VertexInput v)
{
    VertexOutput o = (VertexOutput)0;
    float outlineWidth = _Outline_Width * 0.001;
    o.pos = TransformObjectToHClip(v.vertex.xyz + v.normal * outlineWidth);
    return o;
}

float4 frag(VertexOutput i) : SV_TARGET
{
    return _Outline_Color;
}

#endif