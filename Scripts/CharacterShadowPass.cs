/// How to use
/// 1. Add 'CharacterShadowCamera' prefab to your scene.
/// 2. Add pass to your shader to use 'CharacterShadowDepthPass.hlsl' with "CharacterDepth" LightMode. (See below example)
/* [Pass Example - Unity Toon Shader]
 * NOTE) We assume that the shader use "_ClippingMask" property.
 * Pass
 *   {
 *       Name "CharacterDepth"
 *       Tags{"LightMode" = "CharacterDepth"}
 *
 *       ZWrite On
 *       ZTest LEqual
 *       Cull Off
 *       BlendOp Max
 *
 *       HLSLPROGRAM
 *       #pragma target 2.0
 *   
 *       // Required to compile gles 2.0 with standard srp library
 *       #pragma prefer_hlslcc gles
 *       #pragma exclude_renderers d3d11_9x
 *       #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
 *
 *       #pragma vertex CharShadowVertex
 *       #pragma fragment CharShadowFragment
 *
 *       #include "Packages/com.unity.tooncharactershadow/Shaders/CharacterShadowDepthPass.hlsl"
 *       ENDHLSL
 *   }
 */

using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ToonCharacterShadow
{
    public class CharacterShadowPass : ScriptableRenderPass
    {
        /* ID */
        private static readonly ShaderTagId k_ShaderTagId = new ShaderTagId("CharacterDepth");
        private static class IDs
        {
            public static int _CharShadowMap = Shader.PropertyToID("_CharShadowMap");
            public static int _CharShadowParams = Shader.PropertyToID("_CharShadowParams");
            public static int _ViewMatrix = Shader.PropertyToID("_CharShadowViewM");
            public static int _ProjMatrix = Shader.PropertyToID("_CharShadowProjM");
            public static int _ShadowOffset0 = Shader.PropertyToID("_CharShadowOffset0");
            public static int _ShadowOffset1 = Shader.PropertyToID("_CharShadowOffset1");
            public static int _ShadowMapSize = Shader.PropertyToID("_CharShadowmapSize");
            public static int _CharShadowCascadeParams = Shader.PropertyToID("_CharShadowCascadeParams");
            public static int _UseBrightestLight = Shader.PropertyToID("_UseBrightestLight");
        }


        /* Member Variables */
        private RTHandle m_CharShadowRT;
        private ProfilingSampler m_ProfilingSampler;
        private PassData m_PassData;
        private static int[] s_TextureSize = new int[2] { 1, 1 };
        private CharSoftShadowMode m_SoftShadowMode;
        private float m_cascadeResolutionScale = 1f;
        private float m_cascadeMaxDistance;
        private FilteringSettings m_FilteringSettings;
        

        public CharacterShadowPass(RenderPassEvent evt, RenderQueueRange renderQueueRange)
        {
            m_PassData = new PassData();
            m_FilteringSettings = new FilteringSettings(renderQueueRange);
            renderPassEvent = evt;
        }

        public void Dispose()
        {
            m_CharShadowRT?.Release();
        }

        public void Setup(string featureName, in RenderingData renderingData, CharacterShadowConfig config, bool additionalShadowEnabled)
        {
            m_ProfilingSampler = new ProfilingSampler(featureName);
            m_PassData.bias = new Vector3(config.bias, config.normalBias, 0f);
            m_PassData.stepSmoothness = config.stepSmoothness;
            m_PassData.highSoftShadowBlurDistance = config.highSoftShadowBlurDistance;
            var scale = (int)config.textureScale;
            m_cascadeResolutionScale = CharacterShadowUtils.FindCascadedShadowMapResolutionScale(renderingData, config.cascadeSplit);
            m_cascadeMaxDistance = config.cascadeSplit.w;
            s_TextureSize[0] = 1024 * scale;
            s_TextureSize[1] = 1024 * scale;
            m_PassData.precision = (int)config.precision;
            m_PassData.useBrightestLight = additionalShadowEnabled ? config.useBrightestLight : false;
            m_PassData.followLightLayer = config.followLayerMask;
            m_SoftShadowMode = config.softShadowMode;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var descriptor = new RenderTextureDescriptor(s_TextureSize[0], s_TextureSize[1], (RenderTextureFormat)m_PassData.precision, 0);
            descriptor.dimension = TextureDimension.Tex2D;
            descriptor.sRGB = false;
            // Allocate Char Shadowmap
            RenderingUtils.ReAllocateIfNeeded(ref m_CharShadowRT, descriptor, FilterMode.Bilinear, name:"CharShadowMap");
            cmd.SetGlobalTexture(IDs._CharShadowMap, m_CharShadowRT);

            m_PassData.charShadowRT = m_CharShadowRT;
            cmd.SetGlobalVector(IDs._CharShadowCascadeParams, new Vector4(m_cascadeMaxDistance, m_cascadeResolutionScale, 0, 0));
            cmd.SetGlobalInt(IDs._UseBrightestLight, m_PassData.useBrightestLight ? 1 : 0);
            CoreUtils.SetKeyword(cmd, "_HIGH_CHAR_SOFTSHADOW", m_SoftShadowMode == CharSoftShadowMode.High);
        }

        private static void SetCharShadowConfig(CommandBuffer cmd, PassData passData, ref RenderingData renderingData)
        {
            CharacterShadowUtils.SetShadowmapLightData(cmd, ref renderingData, passData.useBrightestLight, passData.followLightLayer);

            var lightCamera = CharShadowCamera.Instance.lightCamera;
            if (lightCamera != null)
            {
                float widthScale = (float)Screen.width / (float)Screen.height;
                passData.projectM = lightCamera.projectionMatrix;
                passData.viewM = lightCamera.worldToCameraMatrix;
                passData.viewM.m00 *= widthScale;
            }

            // Set global properties
            float invShadowMapWidth = 1.0f / s_TextureSize[0];
            float invShadowMapHeight = 1.0f / s_TextureSize[1];
            float invHalfShadowMapWidth = 0.5f * invShadowMapWidth;
            float invHalfShadowMapHeight = 0.5f * invShadowMapHeight;

            cmd.SetGlobalVector(IDs._CharShadowParams, new Vector4(passData.bias.x, passData.bias.y, passData.stepSmoothness, passData.highSoftShadowBlurDistance));
            cmd.SetGlobalMatrix(IDs._ViewMatrix, passData.viewM);
            cmd.SetGlobalMatrix(IDs._ProjMatrix, passData.projectM);

            cmd.SetGlobalVector(IDs._ShadowOffset0, new Vector4(-invHalfShadowMapWidth, -invHalfShadowMapHeight, invHalfShadowMapWidth, -invHalfShadowMapHeight));
            cmd.SetGlobalVector(IDs._ShadowOffset1, new Vector4(-invHalfShadowMapWidth, invHalfShadowMapHeight, invHalfShadowMapWidth, invHalfShadowMapHeight));
            cmd.SetGlobalVector(IDs._ShadowMapSize, new Vector4(invShadowMapWidth, invShadowMapHeight, s_TextureSize[0], s_TextureSize[1]));
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            m_PassData.filteringSettings = m_FilteringSettings;
            m_PassData.profilingSampler = m_ProfilingSampler;

            ExecuteCharShadowPass(context, m_PassData, ref renderingData);
        }

        private static void ExecuteCharShadowPass(ScriptableRenderContext context, PassData passData, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();
            var filteringSettings = passData.filteringSettings;
            var drawSettings = RenderingUtils.CreateDrawingSettings(k_ShaderTagId, ref renderingData, SortingCriteria.CommonOpaque);

            using (new ProfilingScope(cmd, passData.profilingSampler))
            {
                // Shadowmap
                SetCharShadowConfig(cmd, passData, ref renderingData);
                CoreUtils.SetRenderTarget(cmd, passData.charShadowRT, ClearFlag.Color, 0, CubemapFace.Unknown, 0);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        private class PassData
        {
            public FilteringSettings filteringSettings;
            public ProfilingSampler profilingSampler;
            public Matrix4x4 viewM;
            public Matrix4x4 projectM;
            public Vector3 bias;
            public float stepSmoothness;
            public float highSoftShadowBlurDistance;
            public int precision;
            public bool useBrightestLight;
            public LayerMask followLightLayer;
            public RTHandle charShadowRT;
        }
    }
}