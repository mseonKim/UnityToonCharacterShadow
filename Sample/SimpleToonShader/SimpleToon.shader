Shader "SimpleToon"
{
    Properties
    {
        [Enum(OFF,0,FRONT,1,BACK,2)] _CullMode("Cull Mode", int) = 2  //OFF/FRONT/BACK
        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        _MainTex ("Base Map", 2D) = "white" {}
        [HideInInspector] _BaseMap ("BaseMap", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _ShadeColor ("Shade Color", Color) = (1,1,1,1)
        _BaseColor_Step ("BaseColor Step", Range(0, 1)) = 0.5
        _StepSmoothness ("Step Smoothness", Range(0, 0.5)) = 0.01
        _NormalMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Map Strength", Range(0, 1)) = 0
        _ClippingMask ("Clipping Mask", 2D) = "white" {}

        // Rim Light
        _RimLightColor ("RimLight Color", Color) = (1,1,1,1)
        _Rim_Strength ("Rim Strength", Float) = 4

        // MatCap
        _MatCapColor ("MatCap Color", Color) = (1,1,1,1)
        _MatCapMap ("MatCap Map", 2D) = "black" {}

        // Outline
        _Outline_Color ("Outline Color", Color) = (0,0,0,1)
        _Outline_Width ("Outline Width", Float ) = 0

        // Character Shadow
        [Toggle] _USE_CHAR_SHADOW ("Character Shadow", Float) = 0
    }
    SubShader
    {
        PackageRequirements
        {
             "com.unity.render-pipelines.universal": "14.0.0"
        }    
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }
        Pass
        {
            Name "Outline"
            Tags
            {
                "LightMode"="SRPDefaultUnlit"
            }
            Cull Front

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "SimpleToonInput.hlsl"
            #include "SimpleToonOutlinePass.hlsl"

            ENDHLSL
        }
        Pass
        {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}
            Cull[_CullMode]
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // -------------------------------------
            // Universal Render Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE
            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog

            // -------------------------------------
            // Character Shadow keywords
            #pragma shader_feature _HIGH_CHAR_SOFTSHADOW

            #include "SimpleToonInput.hlsl"
            #include "SimpleToonPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            Cull[_CullMode]

            HLSLPROGRAM
            #pragma target 2.0
	    
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles

            #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "SimpleToonInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull[_CullMode]

            HLSLPROGRAM
            #pragma target 2.0
	    
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #include "SimpleToonInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
        // This pass is used when drawing to a _CameraNormalsTexture texture
        Pass
        {
            Name "DepthNormals"
            Tags{"LightMode" = "DepthNormals"}

            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0	    
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Version.hlsl"


            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _PARALLAXMAP
            #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #include "SimpleToonInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"

            ENDHLSL
        }

        Pass
       {
           Name "CharacterDepth"
           Tags{"LightMode" = "CharacterDepth"}

           ZWrite On
           ZTest LEqual
           Cull Off
           BlendOp Max

           HLSLPROGRAM
           #pragma target 2.0
    
           // Required to compile gles 2.0 with standard srp library
           #pragma prefer_hlslcc gles
           #pragma exclude_renderers d3d11_9x
           #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

           #pragma vertex CharShadowVertex
           #pragma fragment CharShadowFragment

           #include "SimpleToonInput.hlsl"
           #include "Packages/com.unity.tooncharactershadow/Shaders/CharacterShadowDepthPass.hlsl"
           ENDHLSL
       }

       Pass
       {
           Name "TransparentShadow"
           Tags {"LightMode" = "TransparentShadow"}

           ZWrite Off
           ZTest Off
           Cull Off
           Blend One One
           BlendOp Max

           HLSLPROGRAM
           #pragma target 2.0
    
           #pragma prefer_hlslcc gles
           #pragma exclude_renderers d3d11_9x
           #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
           #pragma shader_feature_local _ALPHATEST_ON

           #pragma vertex TransparentShadowVert
           #pragma fragment TransparentShadowFragment

           #include "SimpleToonInput.hlsl"
           #include "Packages/com.unity.tooncharactershadow/Shaders/TransparentShadowPass.hlsl"
           ENDHLSL
       }
       Pass
       {
           Name "TransparentAlphaSum"
           Tags {"LightMode" = "TransparentAlphaSum"}

           ZWrite Off
           ZTest Off
           Cull Off
           Blend One One
           BlendOp Add

           HLSLPROGRAM
           #pragma target 2.0
    
           #pragma prefer_hlslcc gles
           #pragma exclude_renderers d3d11_9x
           #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
           #pragma shader_feature_local _ALPHATEST_ON

           #pragma vertex TransparentAlphaSumVert
           #pragma fragment TransparentAlphaSumFragment

           #include "SimpleToonInput.hlsl"
           #include "Packages/com.unity.tooncharactershadow/Shaders/TransparentShadowPass.hlsl"
           ENDHLSL
       }
    }
}