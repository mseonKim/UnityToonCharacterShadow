/// NOTE)
/// This feature should be used only for character's cloth.
/// Otherwise, the shadow will cast to far object as well.
/// Limitations: Not will behave natural if more than 2 transparent clothes overlapped.

/// How to use
/// 1. Add pass to your shader to use 'TransparentShadowPass.hlsl'
///    with "TransparentShadow" and "TransparentAlphaSum" LightMode. (See below example)
/* [Pass Example - Unity Toon Shader]
 * NOTE) We assume that the shader use "_MainTex" and "_BaseColor", "_ClippingMask" properties.
 *   Pass
 *   {
 *       Name "TransparentShadow"
 *       Tags {"LightMode" = "TransparentShadow"}
 *
 *       ZWrite Off
 *       ZTest Off
 *       Cull Off
 *       Blend One One
 *       BlendOp Max
 *
 *       HLSLPROGRAM
 *       #pragma target 2.0
 *   
 *       #pragma prefer_hlslcc gles
 *       #pragma exclude_renderers d3d11_9x
 *       #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
 *       #pragma shader_feature_local _ALPHATEST_ON
 *
 *       #pragma vertex TransparentShadowVert
 *       #pragma fragment TransparentShadowFragment
 *
 *       #include "Packages/com.unity.tooncharactershadow/Shaders/TransparentShadowPass.hlsl"
 *       ENDHLSL
 *   }
 *   Pass
 *   {
 *       Name "TransparentAlphaSum"
 *       Tags {"LightMode" = "TransparentAlphaSum"}
 *
 *       ZWrite Off
 *       ZTest Off
 *       Cull Off
 *       Blend One One
 *       BlendOp Add
 *
 *       HLSLPROGRAM
 *       #pragma target 2.0
 *   
 *       #pragma prefer_hlslcc gles
 *       #pragma exclude_renderers d3d11_9x
 *       #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
 *       #pragma shader_feature_local _ALPHATEST_ON
 *
 *       #pragma vertex TransparentAlphaSumVert
 *       #pragma fragment TransparentAlphaSumFragment
 *
 *       #include "Packages/com.unity.tooncharactershadow/Shaders/TransparentShadowPass.hlsl"
 *       ENDHLSL
 *   }
 */
 
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

namespace ToonCharacterShadow
{
    public class TransparentShadowPass : ScriptableRenderPass
    {
        /* Static Variables */
        private static readonly ShaderTagId k_ShaderTagId = new ShaderTagId("TransparentShadow");
        private static readonly ShaderTagId k_AlphaSumShaderTagId = new ShaderTagId("TransparentAlphaSum");
        private static int s_TransparentShadowMapId = Shader.PropertyToID("_TransparentShadowMap");
        private static int s_TransparentAlphaSumId = Shader.PropertyToID("_TransparentAlphaSum");
        private static int s_ShadowMapSize = Shader.PropertyToID("_CharTransparentShadowmapSize");
        private static int s_ShadowMapIndex = Shader.PropertyToID("_CharShadowmapIndex");
        private static int[] s_TextureSize = new int[2] { 1, 1 };


        /* Member Variables */
        private RTHandle m_TransparentShadowRT;
        private RTHandle m_TransparentAlphaSumRT;
        private ProfilingSampler m_ProfilingSampler;
        private PassData m_PassData;
        private FilteringSettings m_FilteringSettings;

        public TransparentShadowPass(RenderPassEvent evt, RenderQueueRange renderQueueRange)
        {
            m_PassData = new PassData();
            m_FilteringSettings = new FilteringSettings(renderQueueRange);
            renderPassEvent = evt;
        }

        public void Dispose()
        {
            m_TransparentShadowRT?.Release();
            m_TransparentAlphaSumRT?.Release();
        }

        public void Setup(string featureName, in RenderingData renderingData, CharacterShadowConfig config)
        {
            m_ProfilingSampler = new ProfilingSampler(featureName);
            var scale = (int)config.transparentTextureScale;
            s_TextureSize[0] = 1024 * scale;
            s_TextureSize[1] = 1024 * scale;
            m_PassData.precision = (int)config.precision;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // Depth
            var descriptor = new RenderTextureDescriptor(s_TextureSize[0], s_TextureSize[1], (RenderTextureFormat)m_PassData.precision, 0);
            descriptor.dimension = TextureDimension.Tex2D;
            descriptor.sRGB = false;

            RenderingUtils.ReAllocateIfNeeded(ref m_TransparentShadowRT, descriptor, FilterMode.Bilinear, name:"TransparentShadowMap");
            cmd.SetGlobalTexture(s_TransparentShadowMapId, m_TransparentShadowRT);

            // Alpha Sum
            descriptor.graphicsFormat = GraphicsFormat.R16_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref m_TransparentAlphaSumRT, descriptor, FilterMode.Bilinear, name:"TransparentAlphaSum");
            cmd.SetGlobalTexture(s_TransparentAlphaSumId, m_TransparentAlphaSumRT);

            m_PassData.target = m_TransparentShadowRT;
            m_PassData.alphaSumTarget = m_TransparentAlphaSumRT;

            // Set global properties
            float invShadowMapWidth = 1.0f / s_TextureSize[0];
            float invShadowMapHeight = 1.0f / s_TextureSize[1];

            cmd.SetGlobalVector(s_ShadowMapSize, new Vector4(invShadowMapWidth, invShadowMapHeight, s_TextureSize[0], s_TextureSize[1]));
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            m_PassData.filteringSettings = m_FilteringSettings;
            m_PassData.profilingSampler = m_ProfilingSampler;

            ExecuteTransparentShadowPass(context, m_PassData, ref renderingData);
        }

        private static void ExecuteTransparentShadowPass(ScriptableRenderContext context, PassData passData, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();
            var filteringSettings = passData.filteringSettings;

            using (new ProfilingScope(cmd, passData.profilingSampler))
            {
                cmd.SetGlobalFloat(s_ShadowMapIndex, 0);
                CoreUtils.SetRenderTarget(cmd, passData.target, ClearFlag.Color, 0, CubemapFace.Unknown, 0);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                // Depth & Alpha Sum
                var drawSettings = RenderingUtils.CreateDrawingSettings(k_ShaderTagId, ref renderingData, SortingCriteria.CommonTransparent);
                context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings);

                CoreUtils.SetRenderTarget(cmd, passData.alphaSumTarget, ClearFlag.Color, 0, CubemapFace.Unknown, 0);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                var alphaDrawSettings = RenderingUtils.CreateDrawingSettings(k_AlphaSumShaderTagId, ref renderingData, SortingCriteria.CommonTransparent);
                context.DrawRenderers(renderingData.cullResults, ref alphaDrawSettings, ref filteringSettings);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        private class PassData
        {
            public FilteringSettings filteringSettings;
            public ProfilingSampler profilingSampler;
            public RTHandle target;
            public RTHandle alphaSumTarget;
            public int precision;
        }
    }
}