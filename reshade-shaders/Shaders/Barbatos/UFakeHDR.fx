/*------------------.
| :: Description :: |
'-------------------/
uFakeHDR 

Version 1.2
Author: BarbatosBachiko
License: MIT

About: This shader simulates HDR effects (expected by me) for SDR.

History:
(*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility

Version 1.2:
+ organization

*/

/*---------------.
| :: Includes :: |
'---------------*/
#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/*---------------.
| :: Settings :: |
'---------------*/
uniform float HDRPower < 
    ui_type = "slider";
    ui_label = "HDR Power"; 
    ui_min = 1.0; 
    ui_max = 4.0; 
> = 1.150;

uniform int ToneMappingMethod < 
    ui_type = "combo";
    ui_label = "Tone Mapping Method"; 
    ui_items = "Reinhard\0Filmic\0ACES\0BT.709\0Logarithmic\0Adaptive\0";
> = 5;

uniform bool EnableDithering < 
    ui_category = "Dithering";
    ui_type = "checkbox";
    ui_label = "Enable Dithering"; 
> = false; 

uniform float DitherStrength < 
    ui_category = "Dithering";
    ui_type = "slider";
    ui_label = "Dither Strength"; 
    ui_min = 0.0; 
    ui_max = 1.0; 
> = 0.05; 

uniform float NoiseScale < 
    ui_category = "Dithering";
    ui_type = "slider";
    ui_label = "Noise Scale"; 
    ui_min = 0.1; 
    ui_max = 10.0; 
> = 1.0; 

uniform float NoiseSeed < 
    ui_category = "Dithering";
    ui_type = "slider";
    ui_label = "Noise Seed"; 
    ui_min = 1.0; 
    ui_max = 100000.0; 
> = 43758.5453; 

uniform bool EnableBloom < 
    ui_category = "Bloom";
    ui_type = "checkbox";
    ui_label = "Enable Bloom"; 
> = false;

uniform float BloomStrength < 
    ui_category = "Bloom";
    ui_type = "slider";
    ui_label = "Bloom Strength"; 
    ui_min = 0.0; 
    ui_max = 1.0; 
> = 0.300;

uniform float bloomThreshold < 
    ui_category = "Bloom";
    ui_type = "slider";
    ui_label = "Bloom Threshold"; 
    ui_min = 0.0; 
    ui_max = 1.0; 
> = 0.0; 

uniform float LuminanceAdaptationSpeed < 
    ui_category = "Luminace";
    ui_type = "slider";
    ui_label = "Luminance Adaptation Speed"; 
    ui_min = 0.01; 
    ui_max = 1.0; 
> = 0.1;

/*---------------.
| :: Textures :: |
'---------------*/
texture2D BackBufferTex : COLOR;
sampler BackBuffer
{
    Texture = BackBufferTex;
};

#define textureSize float2(BUFFER_WIDTH, BUFFER_HEIGHT)
static float lastSceneLuminance = 0.0;

/*----------------.
| :: Functions :: |
'----------------*/

float CalculateSceneLuminance(float2 texcoord)
{
    float sampleRadius = 2.0;
    float luminanceSum = 0.0;
    int sampleCount = 0;

    for (int x = -1; x <= 1; x++)
    {
        for (int y = -1; y <= 1; y++)
        {
            float2 offset = float2(x, y) * (sampleRadius / textureSize.x);
            float2 sampleCoord = texcoord + offset;

            if (sampleCoord.x >= 0.0 && sampleCoord.x <= 1.0 && sampleCoord.y >= 0.0 && sampleCoord.y <= 1.0)
            {
                float3 sampleColor = tex2D(BackBuffer, sampleCoord).rgb;
                float luminance = dot(sampleColor, float3(0.2126, 0.7152, 0.0722));

                luminanceSum += luminance;
                sampleCount++;
            }
        }
    }

    float currentLuminance = (sampleCount > 0) ? luminanceSum / sampleCount : 0.0;
    lastSceneLuminance += (currentLuminance - lastSceneLuminance) * LuminanceAdaptationSpeed;

    return lastSceneLuminance;
}

float3 ReinhardToneMapping(float3 color)
{
    const float a = 0.25;
    const float burn = 1.5;
    const float maxLum = 1.0;

    float luminance = dot(color, float3(0.2126, 0.7152, 0.0722)) * 1.2;
    luminance = max(luminance, 0.0001);
    float normalizedLuminance = luminance / (a * maxLum);
    normalizedLuminance = clamp(normalizedLuminance, 0.0, 1.0);
    
    float3 mapped = color * (normalizedLuminance / (normalizedLuminance + 1.0));
    mapped *= 1.2;
    
    return saturate(mapped);
}

float3 ACESFilmicToneMapping(float3 color)
{
    const float A = 2.51;
    const float B = 0.03;
    float3 mapped = (color * (color * A + B)) / (color * (A - 1.0) + 1.0);
    return saturate(mapped);
}

float3 FilmicToneMapping(float3 color)
{
    float3 mapped = (color * (color * 0.6 + 0.4)) / (color + 0.6);
    return saturate(mapped * 1.5);
}

float3 ACESToneMapping(float3 color)
{
    float3 mapped = (color * (color + 0.0245786) - (color * color * 0.000093607)) / (color + 0.000009);
    return saturate(mapped);
}

float3 BTToneMapping(float3 color)
{
    float3 mapped = color * (color * 0.7 + 0.3);
    return saturate(mapped);
}

float3 LogarithmicToneMapping(float3 color)
{
    return log(color + 1.0) / log(2.0);
}

float3 AdaptiveToneMapping(float3 color, float sceneLuminance)
{
    float targetLuminance = 0.5;
    float adaptationSpeed = 0.1;
    float minAdjustment = 0.5;
    float maxAdjustment = 2.0;
    float luminanceAdjustment = targetLuminance / (sceneLuminance + 0.001);
    luminanceAdjustment = clamp(luminanceAdjustment, minAdjustment, maxAdjustment);
    float adjustmentFactor = lerp(1.0, luminanceAdjustment, adaptationSpeed);
    color *= adjustmentFactor;

    return saturate(color);
}

float3 ApplyBloom(float3 color, float2 texcoord)
{
    if (!EnableBloom)
    {
        return color;
    }

    const float localBloomStrength = BloomStrength;
    const float localBloomThreshold = bloomThreshold;
    const float3 luminanceCoefficients = float3(0.2126, 0.7152, 0.0722);

    float luminance = dot(color, luminanceCoefficients);

    if (luminance < localBloomThreshold)
    {
        return color;
    }

    float3 bloomColor = float3(0.0, 0.0, 0.0);
    float totalWeight = 0.0;
    float2 offsetFactor = 1.0 / textureSize;

    for (int x = -2; x <= 2; x++)
    {
        for (int y = -2; y <= 2; y++)
        {
            float2 offset = float2(x, y) * offsetFactor;
            float3 sampleColor = tex2D(BackBuffer, texcoord + offset).rgb;

            float sampleLuminance = dot(sampleColor, luminanceCoefficients);

            if (sampleLuminance > localBloomThreshold)
            {
                float weight = sampleLuminance - localBloomThreshold;
                bloomColor += sampleColor * weight;
                totalWeight += weight;
            }
        }
    }

    if (totalWeight > 0.0)
    {
        bloomColor /= totalWeight;
    }

    return saturate(color + bloomColor * localBloomStrength);
}

float3 ApplyToneMapping(float3 color, float2 texcoord)
{
    float sceneLuminance = CalculateSceneLuminance(texcoord);

    switch (ToneMappingMethod)
    {
        case 0:
            return ReinhardToneMapping(color);
        case 1:
            return FilmicToneMapping(color);
        case 2:
            return ACESToneMapping(color);
        case 3:
            return BTToneMapping(color);
        case 4:
            return LogarithmicToneMapping(color);
        case 5:
            return AdaptiveToneMapping(color, sceneLuminance);
        default:
            return color;
    }
}

float make_noise(float2 uv)
{
    return frac(sin(dot(uv.xy * NoiseScale, float2(12.9898, 78.233))) * NoiseSeed);
}

float3 ApplyDithering(float3 color, float2 texcoord, float DitherStrength)
{
    float noise = make_noise(texcoord * 100.0);
    color += (noise - 0.5) * DitherStrength;

    return saturate(color);
}

float4 uFakeHDRPass(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = tex2D(BackBuffer, texcoord).rgb;
    float3 hdrColor = pow(color, HDRPower);
    
    hdrColor = ApplyToneMapping(hdrColor, texcoord);
    hdrColor = ApplyBloom(hdrColor, texcoord);

    if (EnableDithering)
    {
        hdrColor = ApplyDithering(hdrColor, texcoord, DitherStrength);
    }

    return float4(saturate(hdrColor), 1.0);
}

/*-----------------.
| :: Techniques :: |
'-----------------*/
technique uFakeHDR
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = uFakeHDRPass;
    }
}
