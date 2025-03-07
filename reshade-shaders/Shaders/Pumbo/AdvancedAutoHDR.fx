#include "ReShade.fxh"
#include "Color.fxh"

// These are from the "color_space" enum in ReShade
#define RESHADE_COLOR_SPACE_UNKNOWN     0
#define RESHADE_COLOR_SPACE_SRGB        1
#define RESHADE_COLOR_SPACE_SCRGB       2
#define RESHADE_COLOR_SPACE_BT2020_PQ   3

// "BUFFER_COLOR_SPACE" is defined by ReShade.
// "ACTUAL_COLOR_SPACE" uses the enum values defined in "IN_COLOR_SPACE" below.
#if BUFFER_COLOR_SPACE == RESHADE_COLOR_SPACE_SRGB
  #define ACTUAL_COLOR_SPACE 1
#elif BUFFER_COLOR_SPACE == RESHADE_COLOR_SPACE_SCRGB
  #define ACTUAL_COLOR_SPACE 4
#elif BUFFER_COLOR_SPACE == RESHADE_COLOR_SPACE_BT2020_PQ
  #define ACTUAL_COLOR_SPACE 5
#else
  #define ACTUAL_COLOR_SPACE 0
#endif

// This uses the enum values defined in "IN_COLOR_SPACE"
#define DEFAULT_COLOR_SPACE 2

// We don't default to "Auto" here as if we are upgrading the backbuffer, we'd detect the wrong value
uniform uint IN_COLOR_SPACE
<
  ui_label    = "Input Color Space";
  ui_type     = "combo";
  ui_items    = "Auto\0SDR sRGB\0SDR Rec.709 Gamma 2.2\0SDR Rec.709 Gamma 2.4\0HDR scRGB\0HDR10 (BT.2020 PQ)\0";
  ui_tooltip = "Specify the input color space (\"Auto\" is usually correct).\nMost SDR games targeted \"Gamma 2.2\", though some targeted \"sRGB\", pick the one that looks more correct.\nFor HDR, either pick \"scRGB\" or \"HDR10\".";
  ui_category = "Calibration";
> = DEFAULT_COLOR_SPACE;

uniform float OUTPUT_WHITE_LEVEL_NITS
<
  ui_label = "Output white level (paper white) nits";
  ui_type = "drag";
  ui_tooltip = "Controls how bright the output image is. A value of 80 nits is \"neutral\" (it's the sRGB SDR standard),\nthough for most viewing conditions 203 is a good starting point (ITU reference value).\nLeave at 80 if the source image is already HDR (unless you want to change its brightness).";
  ui_category = "Calibration";
  ui_min = 1.f;
  ui_max = 500.f;
  ui_step = 1.f;
> = sRGB_max_nits;

uniform uint OUT_OF_GAMUT_COLORS_BEHAVIOUR
<
  ui_label    = "Out of gamut colors behaviour";
  ui_type     = "combo";
  ui_items    = "Apply Gamma\0Ignore Gamma\0Clip\0";
  ui_tooltip = "When forcing HDR (float) buffers on SDR games, they can occasionally output rgb colors brighter than 1 or lower than 0.\nThis dictates how we should react to them. Pick what looks best.";
  ui_category = "Advanced calibration";
> = 0;

uniform uint OUT_COLOR_SPACE
<
  ui_label    = "Output Color Space";
  ui_type     = "combo";
  ui_items    = "Auto\0HDR scRGB\0HDR10 (BT.2020 PQ)\0Force Input Color Space\0";
  ui_tooltip = "Specify the output color space";
  ui_category = "Advanced calibration";
> = 0;

//TODO: either add a preprocessor condition to always show this setting or turn "IN_COLOR_SPACE" into a preprocessor condition (not user friendly)
uniform uint FIX_SRGB_2_2_GAMMA_MISMATCH_TYPE
<
  ui_label    = "Fix sRGB gamma / 2.2 gamma mismatch";
  ui_type     = "combo";
  hidden      = ACTUAL_COLOR_SPACE < 4;
  ui_items    = "None\0By channel - RECCOMENDED\0By luminance (color hue conserving)\0";
  ui_tooltip = "Some games use the sRGB gamma formula on output, but were developed and calibrated on gamma 2.2 displays.\nThis mismatch is usually baked into the game's look, so it looks correct in SDR on gamma 2.2 screens,\nbut it needs to be acknowledged when upgrading SDR to HDR (or there will be raised blacks), as we need to use the right inverse gamma formula.\nOccasionally this mismatch also ended up baked in the game's native HDR look, so you can use this to fix raised blacks.";
  ui_category = "Advanced calibration";
> = 0;

uniform float SOURCE_HDR_WHITE_LEVEL_NITS
<
  ui_label = "Input HDR white level (paper white) nits";
  hidden   = ACTUAL_COLOR_SPACE < 4;
  ui_type = "drag";
  ui_tooltip = "What paper white did the (native) HDR source image have? This should be matched with the game paper white HDR calibration setting.\nUse 203 if you can't find out the value from the game (it's usually between 200 and 300).\nSet to 80 if the game was rendering to SDR but has been upgraded to HDR (e.g. SpecialK, DXVK).\nThis has the opposite effect of the \"Output white level\" setting.\nThis might be ignored if the source image was SDR.";
  ui_category = "Advanced calibration";
  ui_min = 1.f;
  ui_max = 500.f;
  ui_step = 1.f;
> = sRGB_max_nits;

uniform bool HDR_TONEMAP
<
  ui_label = "HDR tonemapping";
  ui_tooltip = "Enables an additional HDR tonemapping pass that happens after Auto HDR techniques. It can be useful to tonemap games that ignore the user display peak brightness.";
  ui_category = "HDR tonemapping";
> = false;

uniform float HDR_SOURCE_PEAK_WHITE
<
  ui_label = "Input HDR peak white level nits";
  ui_tooltip = "In case the game was already tonemapping to HDR but targeted a specific peak brightness level that doesn't match your display (e.g. some games don't offer HDR calibration),\nyou can specify the value here, it will help in adjusting the tonemap curve to be more accurate.\nSet to 0 to ignore.";
  ui_category = "HDR tonemapping";
  ui_type = "drag";
  ui_min = 0.f;
  ui_max = 10000.f;
  ui_step = 1.f;
> = 0.f;

uniform float HDR_PEAK_WHITE
<
  ui_label = "HDR display peak brightness (max nits)";
  ui_tooltip = "Set it equal or higher than \"Auto HDR target/max brightness\" to avoid double tonemapping. HDR usually doesn't go lower than 400 nits.";
  ui_category = "HDR tonemapping";
  ui_type = "drag";
  ui_min = sRGB_max_nits;
  ui_max = 10000.f;
  ui_step = 1.f;
> = 750.f;

uniform float HDR_HIGHLIGHTS_SHOULDER_START_ALPHA
<
  ui_label = "Highlights shoulder start alpha";
  ui_tooltip = "When do we start compressing the highlights to be within the brightness range of your display?\nHigher values will have steeper gradients around highlights and midtones.\nLower values will have a small effect on shadow too, but could look more smooth.";
  ui_category = "HDR tonemapping";
  ui_type = "drag";
  ui_min = 0.f;
  ui_max = 1.f;
  ui_step = 0.01f;
> = 0.5f;

uniform uint AUTO_HDR_METHOD
<
  ui_category = "Auto HDR (SDR->HDR)";
  ui_label    = "Auto HDR method";
  ui_type     = "combo";
  ui_items    = "None\0By luminance (color hue conserving) - RECCOMENDED\0By channel average (color hue conserving)\0By channel (increases saturation)\0By channel with hue restoration (~color hue conserving)\0By max channel (color hue conserving)\0By luminance and max channel (color hue conserving)\0By Oklab lightness (perceptual color hue conserving)\0";
> = 0;

uniform float AUTO_HDR_SHOULDER_START_ALPHA
<
  ui_label = "Auto HDR shoulder start alpha";
  ui_tooltip = "Determines how bright the source SDR color needs to be before we start scaling its brightness to generate fake HDR highlights. Has no effect at 1.";
  ui_category = "Auto HDR (SDR->HDR)";
  ui_type = "drag";
  ui_min = 0.f;
  ui_max = 1.f;
  ui_step = 0.01f;
> = 0.f;

uniform float AUTO_HDR_MAX_NITS
<
  ui_label = "Auto HDR target/max brightness";
  ui_tooltip = "Depending on the other Auto HDR settings, going too bright (e.g. beyond the 600-1000 nits range), can lead to weird results,\nas we are still limited by a low bit depth SDR source image.\nThis applies on the normalized image, so it should be considered as relative to the SDR range (with 80 nits being the baseline peak white).";
  ui_category = "Auto HDR (SDR->HDR)";
  ui_type = "drag";
  ui_min = sRGB_max_nits;
  ui_max = 2000.f;
  ui_step = 1.f;
> = 400.f;

uniform float AUTO_HDR_SHOULDER_POW
<
  ui_label = "Auto HDR shoulder pow";
  ui_tooltip = "Modulates the Auto HDR highlights curve";
  ui_category = "Auto HDR (SDR->HDR)";
  ui_type = "drag";
  ui_min = 1.f;
  ui_max = 10.f;
  ui_step = 0.05f;
> = 2.5f;

uniform uint INVERSE_TONEMAP_METHOD
<
  ui_category = "Inverse tone mapping (alternative SDR->HDR)";
  ui_label    = "Inverse tonemap method";
  ui_tooltip  = "Do not use with Auto HDR; it's a more bare bones version of it.\nSome of these might clip all out of gamut colors from the source image.";
  ui_type     = "combo";
  ui_items    = "None\0Advanced Reinhard (by channel)\0ACES Filmic (by channel)\0";
> = 0;

uniform float TONEMAPPER_WHITE_LEVEL
<
  ui_label = "Tonemapper white level (in units)";
  ui_tooltip = "Used as parameter by some (inverse) tonemappers. Increases saturation. Has no effect at 1.";
  ui_category = "Inverse tone mapping (alternative SDR->HDR)";
  ui_type = "drag";
  ui_min = 1.f;
  ui_max = 100.f;
  ui_step = 0.01f;
> = 2.f;

uniform float INVERSE_TONEMAP_COLOR_CONSERVATION
<
  ui_label = "Inverse tonemapper color conservation";
  ui_tooltip = "This makes the inverse tonemapped color gradually restore the SDR source image color (hue and saturation/chroma), while retaining its increased perceived brightness.\nAvoid setting this too close to one as it could cause problems in some scenes.";
  ui_category = "Inverse tone mapping (alternative SDR->HDR)";
  ui_type = "drag";
  ui_min = 0.f;
  ui_max = 1.f;
  ui_step = 0.01f;
> = 0.0f;

uniform float BLACK_FLOOR_LUMINANCE
<
  ui_label = "Black floor luminance";
  ui_tooltip = "Fixes raised black floors by remapping colors (by luminance). Relative to the input white level.";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.0f;
  ui_max = mid_gray;
  ui_step = 0.0000005f;
> = 0.f;

uniform float SHADOW_TUNING
<
  ui_label = "Shadow";
  ui_tooltip = "Rebalances shadows. Relative to the input white level. Neutral at 1.";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.01f;
  ui_max = 10.f;
  ui_step = 0.01f;
> = 1.f;

uniform float HIGHLIGHT_SATURATION
<
  ui_label = "Highlight saturation";
  ui_tooltip = "Allows tuning of highlights saturation (vibrancy). Relative to the input white level. Neutral at 1.";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.75f;
  ui_max = 1.5f;
  ui_step = 0.005f;
> = 1.f;

uniform float EXTRA_HDR_SATURATION
<
  ui_label = "Extra HDR saturation";
  ui_tooltip = "Generates HDR colors (BT.2020) from bright saturated SDR (BT.709) ones. Neutral at 0.";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.f;
  ui_max = 1.f;
  ui_step = 0.01f;
> = 0.f;

void AdvancedAutoHDR(
      float4 vpos : SV_Position,
      float2 texcoord : TEXCOORD,
  out float4 output : SV_Target0)
{
    const float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;

    float3 fixedGammaColor = input;
    fixedGammaColor = clamp(fixedGammaColor, -FLT16_MAX, FLT16_MAX);
    
    uint inColorSpace = IN_COLOR_SPACE;
    if (inColorSpace == 0) // Auto selection
    {
        if (ACTUAL_COLOR_SPACE == 0) // Fall back on default if the actual color space is unknown
            inColorSpace = DEFAULT_COLOR_SPACE;
        else
            inColorSpace = ACTUAL_COLOR_SPACE;
    }
    
    const bool ignoreOutOfGamutColorsGamma = OUT_OF_GAMUT_COLORS_BEHAVIOUR == 1;
    const bool clipOutOfGamutColors = OUT_OF_GAMUT_COLORS_BEHAVIOUR == 2;

    if (inColorSpace == 0 || inColorSpace == 1) // sRGB (and Auto)
        fixedGammaColor = sRGB_to_linear(fixedGammaColor, ignoreOutOfGamutColorsGamma);
    else if (inColorSpace == 2 || inColorSpace == 3) // Rec.709 Gamma 2.2 | Rec.709 Gamma 2.4
    {
        const float gamma = (inColorSpace == 2) ? 2.2f : 2.4f;
        
        float3 extraColor = 0.f;
        if (ignoreOutOfGamutColorsGamma)
        {
            extraColor = fixedGammaColor - saturate(fixedGammaColor);
            fixedGammaColor = saturate(fixedGammaColor);
        }
        
        fixedGammaColor = gamma_to_linear_mirrored(fixedGammaColor, gamma);
        fixedGammaColor += extraColor;

    }
    else if (inColorSpace == 5) // HDR10 BT.2020 PQ
    {
        fixedGammaColor = PQ_to_linear(fixedGammaColor); // We use sRGB white level (80 nits, not 100)
        fixedGammaColor = BT2020_to_BT709(fixedGammaColor);
    }
    
    if (clipOutOfGamutColors)
    {
        fixedGammaColor = saturate(fixedGammaColor);
    }
    
    // Divide by a user selected Paper White value (the same one the user set in the game (if playing in scRGB/HDR10)), and then re-multiply by it after at the end, so everything is roughly independent from the paper white and run around a white level of 80.
    float brightnessScale = inColorSpace >= 4 ? (SOURCE_HDR_WHITE_LEVEL_NITS / sRGB_max_nits) : 1.f;
    fixedGammaColor /= brightnessScale;
    
    if (FIX_SRGB_2_2_GAMMA_MISMATCH_TYPE > 0 && ACTUAL_COLOR_SPACE >= 4) // Check "FIX_SRGB_2_2_GAMMA_MISMATCH" hiding condition as well
    {
        // Ignore any out of range values, we don't want to affect them with a random gamma shift (especially if the source was HDR and already had values beyond 0-1, where gamma theoretically isn't defined)
        const float3 extraColor = fixedGammaColor - saturate(fixedGammaColor);
        fixedGammaColor = saturate(fixedGammaColor);
        
        const float fixedGammaColorLuminance = luminance(fixedGammaColor);
        float3 intermediaryFixedGammaColor = fixedGammaColor;
        if (FIX_SRGB_2_2_GAMMA_MISMATCH_TYPE == 2) // Hue conserving method (unorthodox)
        {
            intermediaryFixedGammaColor = fixedGammaColorLuminance; // Only rely on the first channel
        }
        // No need to run the mirrored gamma functions here given we clipped values beyond 0-1, but we do it anyway
        intermediaryFixedGammaColor = linear_to_sRGB_mirrored(intermediaryFixedGammaColor);
        intermediaryFixedGammaColor = gamma_to_linear_mirrored(intermediaryFixedGammaColor, 2.2f);
        if (FIX_SRGB_2_2_GAMMA_MISMATCH_TYPE == 2)
        {
            fixedGammaColor *= fixedGammaColorLuminance != 0.f ? (intermediaryFixedGammaColor.x / fixedGammaColorLuminance) : 1.f;
        }
        else
        {
            fixedGammaColor = intermediaryFixedGammaColor;
        }
        
        fixedGammaColor += extraColor;
    }

    // Fix up negative luminance (imaginary/invalid colors)
    if (luminance(fixedGammaColor) < 0.f)
        fixedGammaColor = 0.f;
    
    // Fix raised blacks floor
    float3 fineTunedColor = fixedGammaColor;
    // Just do it by luminance for now, even if average or per channel might be better
    const float preRaisedBlacksFixLuminance = luminance(fineTunedColor);
    if (preRaisedBlacksFixLuminance > 0.f)
    {
        const float postRaisedBlacksFixLuminance = max(preRaisedBlacksFixLuminance - BLACK_FLOOR_LUMINANCE, 0.f);
        fineTunedColor *= (postRaisedBlacksFixLuminance / preRaisedBlacksFixLuminance) * (1.f / (1.f - BLACK_FLOOR_LUMINANCE));
    }
    
#if 0 // Remap shadows (per channel)
    fineTunedColor = remapFromZero(fineTunedColor, 0.f, SHADOW_TUNING, mid_gray * 0.5f);
#else // Remap shadows (luminance based)
    const float preFineTuningLuminance = luminance(fineTunedColor);
    if (preFineTuningLuminance > 0.f)
    {
        const float postFineTuningLuminance = remapFromZero(preFineTuningLuminance.xxx, 0.f, SHADOW_TUNING, mid_gray * 0.5f).x;
        fineTunedColor *= postFineTuningLuminance / preFineTuningLuminance;
    }
#endif

    float3 fixTonemapColor = fineTunedColor;
    if (INVERSE_TONEMAP_METHOD > 0)
    {
        if (INVERSE_TONEMAP_METHOD == 1) // Advanced Reinhard - Component based
        {
            fixTonemapColor = inv_tonemap_ReinhardPerComponent(fixTonemapColor, TONEMAPPER_WHITE_LEVEL);
            
            // Re-map the image to roughly keep the same average brightness
            fixTonemapColor *= mid_gray / average(inv_tonemap_ReinhardPerComponent(mid_gray, TONEMAPPER_WHITE_LEVEL));
        }
        else if (INVERSE_TONEMAP_METHOD == 2) // (Approximate) ACES Filmic
        {
            fixTonemapColor = inv_ACES_Filmic(fixTonemapColor);
            
            fixTonemapColor *= mid_gray / average(inv_ACES_Filmic(mid_gray));
        }
#if 0 // Disabled as it's unlikely to ever have been used by SDR games (tonemapping by luminance can create colors beyond 1) and it looks ugly
        else if (INVERSE_TONEMAP_METHOD == 3) // Advanced Reinhard - Luminance based
        {
            const float PreTonemapLuminance = luminance(fixTonemapColor);
            const float PostTonemapLuminance = inv_tonemap_ReinhardPerComponent(PreTonemapLuminance, TONEMAPPER_WHITE_LEVEL).r;
            fixTonemapColor *= PostTonemapLuminance / PreTonemapLuminance;
        }
#endif
        //TODO: add some other inverse tonemappers and SpecialK Perceptual Boost
        
        // Restore part of the original color "saturation" and "hue", but keep the new luminance
        if (INVERSE_TONEMAP_COLOR_CONSERVATION != 0.f)
        {
#if 1 //TODO: test... is this working? It doesn't seem to look that good
            fixTonemapColor = RestoreHue(fixTonemapColor, fineTunedColor, INVERSE_TONEMAP_COLOR_CONSERVATION);
#else //TODO: delete old implementation?
            //TODO: experiment with this more (separate hue and chroma sliders?)
            const float3 preInverseTonemapOklch = linear_srgb_to_oklch(fineTunedColor);
            float3 postInverseTonemapOklch = linear_srgb_to_oklch(fixTonemapColor);
            postInverseTonemapOklch.yz = lerp(postInverseTonemapOklch.yz, preInverseTonemapOklch.yz, INVERSE_TONEMAP_COLOR_CONSERVATION);
            fixTonemapColor = oklch_to_linear_srgb(postInverseTonemapOklch);
#endif
        }
    }
    brightnessScale *= OUTPUT_WHITE_LEVEL_NITS / sRGB_max_nits;

    // Auto HDR
    const bool doAutoHDR = AUTO_HDR_METHOD > 0 && AUTO_HDR_SHOULDER_START_ALPHA < 1.f;
    float3 autoHDRColor = fixTonemapColor;
    if (doAutoHDR)
    {
        float3 SDRRatio = 0.f;
        float3 divisor = 1.f;
        float autoHDRShoulderPow = AUTO_HDR_SHOULDER_POW;
        float autoHDRBrightnessScale = brightnessScale;
        float autoHDRMaxNits = AUTO_HDR_MAX_NITS;
        float autoHDRGamma = 1.f;
        
        //TODO: delete all except luminance, average and channel? People seem to like weird ones
        
        // By luminance
        if (AUTO_HDR_METHOD == 1)
        {
            SDRRatio = luminance(autoHDRColor);
        }
        // By average
        else if (AUTO_HDR_METHOD == 2)
        {
            SDRRatio = average(autoHDRColor);
        }
        // By channel
        else if (AUTO_HDR_METHOD == 3)
        {
            SDRRatio = autoHDRColor;
            
#if 0 // Disabled as this is currently broken. I don't think it ever worked.
            // Divide by luminance to make Auto HDR stronger on weaker channels, otherwise it's not really balanced visually
            divisor = K_BT709 / max3(K_BT709.x, K_BT709.y, K_BT709.z);
#endif
        }
        // By channel with hue restoration
        else if (AUTO_HDR_METHOD == 4)
        {
            SDRRatio = autoHDRColor;
        }
        // By max channel
        else if (AUTO_HDR_METHOD == 5)
        {
            SDRRatio = max3(autoHDRColor.x, autoHDRColor.y, autoHDRColor.z);
        }
        // By a blend of luminance and max channel (from MaxG3D)
        else if (AUTO_HDR_METHOD == 6)
        {
            SDRRatio = lerp(max3(autoHDRColor.x, autoHDRColor.y, autoHDRColor.z), luminance(autoHDRColor), 2.f / 3.f); // lerp value found empirically
        }
        // By OKLAB perceived lightness (~perceptually accurate)
        // This is perception space so it likely requires different AutoHDR settings.
        else if (AUTO_HDR_METHOD == 7)
        {
            autoHDRColor = linear_srgb_to_oklab(autoHDRColor);
            SDRRatio = autoHDRColor[0]; // OKLAB lightness
            // Some modifiers to align the results to the other AutoHDR methods (Oklab uses gamma 3 internally)
            autoHDRShoulderPow = pow(autoHDRShoulderPow, 1.5f); // Gamma 3 seems worse here, value found empirically
            autoHDRGamma = 1.f / 3.f; // This makes the resulting peak brightness match the target one
        }
        // Old OKLAB method, use AUTO_HDR_METHOD 7 instead.
        // Note: This seems to be almost identical to the method by luminance (though with slightly different params), so maybe it's useless.
        else if (AUTO_HDR_METHOD == 8)
        {
            SDRRatio = linear_srgb_to_oklab(autoHDRColor)[0];
        }
        
        SDRRatio = max(SDRRatio, AUTO_HDR_SHOULDER_START_ALPHA);
        const float autoHDRMaxWhite = max(autoHDRMaxNits / autoHDRBrightnessScale, sRGB_max_nits) / sRGB_max_nits;
        const float3 autoHDRShoulderRatio = 1.f - (max(1.f - SDRRatio, 0.f) / (1.f - AUTO_HDR_SHOULDER_START_ALPHA));
        const float3 autoHDRExtraRatio = (pow(max(autoHDRShoulderRatio, 0.f), autoHDRShoulderPow) * (pow(autoHDRMaxWhite, autoHDRGamma) - 1.f)) / divisor;
        const float3 autoHDRTotalRatio = SDRRatio + autoHDRExtraRatio;
        
        if (AUTO_HDR_METHOD == 7) // Only scale lightness channel in OKLAB
        {
            autoHDRColor[0] *= SDRRatio[0] != 0.f ? (autoHDRTotalRatio[0] / SDRRatio[0]) : 1.f;
            autoHDRColor = oklab_to_linear_srgb(autoHDRColor);
        }
        else
        {
            autoHDRColor *= SDRRatio != 0.f ? (autoHDRTotalRatio / SDRRatio) : 1.f;
        }

#if 1
        // Restore chroma and hue
        if (AUTO_HDR_METHOD == 4)
        {
            const float3 preAutoHDROklch = linear_srgb_to_oklch(fixTonemapColor);
            float3 postAutoHDROklch = linear_srgb_to_oklch(autoHDRColor);
            postAutoHDROklch.yz = lerp(postAutoHDROklch.yz, preAutoHDROklch.yz, 0.75); // lerp value found empirically (reaching one can be a bit too much), for now we don't expose it
            autoHDRColor = oklch_to_linear_srgb(postAutoHDROklch);
        }
#elif 0 // This doesn't seem to look right (e.g. Red Dead Redeption sky), needs more investigation
        if (AUTO_HDR_METHOD == 4 && INVERSE_TONEMAP_COLOR_CONSERVATION > 0)
        {
            autoHDRColor = RestoreHue(autoHDRColor, fixTonemapColor, INVERSE_TONEMAP_COLOR_CONSERVATION);
        }
#endif
    }
    
    fineTunedColor = autoHDRColor;
    if (HIGHLIGHT_SATURATION != 1.f)
    {
        const float OklabLightness = linear_srgb_to_oklab(fineTunedColor)[0];
        const float highlightSaturationRatio = max((OklabLightness - (2.f / 3.f)) / (1.f / 3.f), 0.f);
        fineTunedColor = saturation(fineTunedColor, lerp(1.f, HIGHLIGHT_SATURATION, highlightSaturationRatio));
    }

    float3 displayMappedColor = fineTunedColor;

    // Note: this is influenced by the AutoHDR params.
    // Theoretically this should be done when the image is fully in linear space,
    // like 0-10k nits or more, before tonemapping, but we can't recreate such image from the data we have.
    if (EXTRA_HDR_SATURATION > 0.f)
    {
        // Do this with a paper white of 203 nits, so it's balanced (the formula seems to be made for that),
        // and gives consistent results independently of the user paper white
        const float recommendedBrightnessScale = ReferenceWhiteNits_BT2408 / sRGB_max_nits;
        
        fineTunedColor = displayMappedColor * recommendedBrightnessScale;
        fineTunedColor = expandGamut(fineTunedColor, EXTRA_HDR_SATURATION);
        displayMappedColor = fineTunedColor / recommendedBrightnessScale;
    }
    
    displayMappedColor *= brightnessScale;
    
    float HDRLuminance = luminance(displayMappedColor);
    
    // Display mapping.
    // Avoid doing it if we are doing AutoHDR within the screen brightness range already (even the result might snap based on the condition when we change params).
    if (HDR_TONEMAP && HDRLuminance > 0.0f)
    {
        const float maxOutputLuminance = HDR_PEAK_WHITE / sRGB_max_nits;
        const float highlightsShoulderStart = HDR_HIGHLIGHTS_SHOULDER_START_ALPHA * maxOutputLuminance;
        const float compressedHDRLuminance = luminanceCompress(HDRLuminance, maxOutputLuminance, highlightsShoulderStart, HDR_SOURCE_PEAK_WHITE > 0.f, HDR_SOURCE_PEAK_WHITE / sRGB_max_nits);
        displayMappedColor *= compressedHDRLuminance / HDRLuminance;
    }

    displayMappedColor = fixNAN(displayMappedColor);

    if (OUT_COLOR_SPACE == 3)
    {
        if (inColorSpace == 1)
        {
            displayMappedColor = linear_to_sRGB_mirrored(displayMappedColor);
        }
        else if (inColorSpace == 2 || inColorSpace == 3)
        {
            const float gamma = (inColorSpace == 2) ? 2.2f : 2.4f;
            displayMappedColor = linear_to_gamma_mirrored(displayMappedColor, gamma);
        }
    }
    if (((OUT_COLOR_SPACE == 0 || OUT_COLOR_SPACE == 3) && inColorSpace == 5)  || OUT_COLOR_SPACE == 2)
    {
        displayMappedColor = BT709_to_BT2020(displayMappedColor);
        displayMappedColor = linear_to_PQ(displayMappedColor);
    }

    output = float4(displayMappedColor, 1.f);
}

technique AdvancedAutoHDR
<
ui_tooltip = "This shader can extrapolate HDR from SDR.\nIt's meant to be used on SDR games with a hook (e.g. DXVK or SpecialK or RenoDX) that is able to replace the game buffers to float16 format (scRGB).\nIt also works on games with native HDR, aiding in fixing the lack of tonemapping, highlights or user paper white adjustment setting.\nIn some cases, RESTIR can help move this shader to draw before the game's UI drew.";
>
{
    pass AdvancedAutoHDR
    {
        VertexShader = PostProcessVS;
        PixelShader = AdvancedAutoHDR;
    }
}
