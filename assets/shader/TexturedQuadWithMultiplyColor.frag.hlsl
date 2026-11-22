Texture2D uTexture : register(t0, space2);
SamplerState uSampler : register(s0, space2);

cbuffer UBO : register(b0, space3)
{
    float4 MultiplyColor : packoffset(c0);
};

float4 main(float2 TexCoord : TEXCOORD0) : SV_Target0
{
    return uTexture.Sample(uSampler, TexCoord) * MultiplyColor;
}
