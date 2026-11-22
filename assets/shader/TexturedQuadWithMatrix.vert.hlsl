// row_major matches the layout of Jai's Math.Matrix4 in memory: row 1 first, translation in the
// last column. HLSL's default for a cbuffer matrix is column_major, which would read it transposed
// and transpose the transform as well.
cbuffer UBO : register(b0, space1)
{
    row_major float4x4 MatrixTransform : packoffset(c0);
};

struct Input
{
    float3 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct Output
{
    float2 TexCoord : TEXCOORD0;
    float4 Position : SV_Position;
};

Output main(Input input)
{
    Output output;
    output.TexCoord = input.TexCoord;
    output.Position = mul(MatrixTransform, float4(input.Position, 1.0f));
    return output;
}
