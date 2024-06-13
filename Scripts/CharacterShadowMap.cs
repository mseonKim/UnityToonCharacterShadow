using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Unity.Collections;
using System.Collections.Generic;

namespace ToonCharacterShadow
{
    public class CharacterShadowMap : ScriptableRendererFeature
    {
        private CharacterShadowPass m_CharShadowPass;
        private TransparentShadowPass m_CharTransparentShadowPass;
        public CharacterShadowConfig config;
        [Tooltip("Link this renderer data")]
        public UniversalRendererData urpData;


        public override void Create()
        {
            m_CharShadowPass = new CharacterShadowPass(RenderPassEvent.BeforeRenderingPrePasses, RenderQueueRange.opaque);
            m_CharShadowPass.ConfigureInput(ScriptableRenderPassInput.None);
            m_CharTransparentShadowPass = new TransparentShadowPass(RenderPassEvent.BeforeRenderingOpaques, RenderQueueRange.transparent);
            m_CharTransparentShadowPass.ConfigureInput(ScriptableRenderPassInput.None);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (config == null)
                return;

            if (!CharacterShadowUtils.IfCharShadowUpdateNeeded(renderingData))
                return;

            if (renderingData.cameraData.cameraType == CameraType.Reflection)
                return;

            // Additional shadow is only available in forward+
            bool additionalShadowEnabled = urpData != null ? urpData.renderingMode == RenderingMode.ForwardPlus : false;
            
            m_CharShadowPass.Setup("CharacterShadowMap", renderingData, config, additionalShadowEnabled);
            renderer.EnqueuePass(m_CharShadowPass);
            if (config.enableTransparentShadow)
            {
                m_CharTransparentShadowPass.Setup("TransparentShadowMap", renderingData, config);
                renderer.EnqueuePass(m_CharTransparentShadowPass);
            }
        }

        protected override void Dispose(bool disposing)
        {
            m_CharShadowPass.Dispose();
            m_CharTransparentShadowPass.Dispose();
        }

    }
}