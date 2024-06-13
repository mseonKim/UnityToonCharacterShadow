using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Unity.Collections;

namespace ToonCharacterShadow
{
    public static class CharacterShadowUtils
    {
        private const float CHAR_SHADOW_CULLING_DIST = 18.0f;
        private static List<VisibleLight> s_vSpotLights = new List<VisibleLight>(256);
        private static List<int> s_vSpotLightIndices = new List<int>(256);
        private static List<KeyValuePair<float, int>> s_SortedSpotLights = new List<KeyValuePair<float, int>>(256);
        private static int s_CharShadowLocalLightIndex = Shader.PropertyToID("_CharShadowLocalLightIndex");
        private static int s_BrightestLightDirection = Shader.PropertyToID("_BrightestLightDirection");

        public static bool IfCharShadowUpdateNeeded(in RenderingData renderingData)
        {
            var cameraWorldPos = renderingData.cameraData.camera.transform.position;
            if (CharShadowCamera.Instance == null || CharShadowCamera.Instance.activeTarget == null)
            {
                return false;
            }
            var charWorldPos = CharShadowCamera.Instance.activeTarget.position;
            var diff = Vector3.Distance(cameraWorldPos,charWorldPos);
            return diff < CHAR_SHADOW_CULLING_DIST;
        }

        ///<returns>
        /// CharShadowMap Cascade index - 1(near), 0.5, 0.25, 0.125(far)
        ///</returns>
        public static float FindCascadedShadowMapResolutionScale(in RenderingData renderingData, Vector4 cascadeSplit)
        {
            var cameraWorldPos = renderingData.cameraData.camera.transform.position;
            if (CharShadowCamera.Instance == null || CharShadowCamera.Instance.activeTarget == null)
            {
                return 0.125f;
            }
            var charWorldPos = CharShadowCamera.Instance.activeTarget.position;
            var diff = Vector3.Distance(cameraWorldPos, charWorldPos);
            if (diff < cascadeSplit.x)
                return 1f;
            else if (diff < cascadeSplit.y)
                return 0.5f;
            else if (diff < cascadeSplit.z)
                return 0.25f;
            return 0.125f;
        }

        /// <summary>
        /// 1. if (useBrighestLightOnly == true) : LightIndex = spot or mainLight.
        /// 2. if (useBrighestLightOnly == false) : LightIndex = mainLight
        /// </summary>
        public static void SetShadowmapLightData(CommandBuffer cmd, ref RenderingData renderingData, bool useBrighestLight, LayerMask followLightLayer)
        {
            var spotLightIndices = CalculateMostIntensiveLightIndices(ref renderingData, followLightLayer);
            var visibleLights = renderingData.lightData.visibleLights;
            if (spotLightIndices == null || (spotLightIndices[0] < 0 && spotLightIndices[1] < 0))
            {
                if (renderingData.lightData.mainLightIndex != -1)
                {
                    CharShadowCamera.Instance.SetLightCameraTransform(visibleLights[renderingData.lightData.mainLightIndex].light);
                    cmd.SetGlobalVector(s_BrightestLightDirection, -visibleLights[renderingData.lightData.mainLightIndex].light.transform.forward);
                }
                return;
            }

            var lightCount = renderingData.lightData.visibleLights.Length;
            var lightOffset = 0;
            while (lightOffset < lightCount && visibleLights[lightOffset].lightType == LightType.Directional)
            {
                lightOffset++;
            }
            var hasMainLight = 0;

            float mainLightStrength = 0f;
            int brightestLightIndex = -1;
            int brightestSpotLightIndex = -1;
            var brightestLightDirection = new Vector3(0, -1, 0);

            // Find stronger light among mainLight & brighest spot light
            if (renderingData.lightData.mainLightIndex != -1 && lightOffset != 0)
            {
                hasMainLight = 1;
                brightestSpotLightIndex = spotLightIndices[0] + hasMainLight;
                brightestLightIndex = renderingData.lightData.mainLightIndex;

                var mainLight = visibleLights[renderingData.lightData.mainLightIndex].light;
                var mainLightColor = mainLight.color * mainLight.intensity;
                mainLightStrength = mainLightColor.r * 0.299f + mainLightColor.g * 0.587f + mainLightColor.b * 0.114f;
            }
            else
            {
                if (spotLightIndices[0] >= 0)
                {
                    brightestLightIndex = brightestSpotLightIndex = spotLightIndices[0] + hasMainLight;
                }
                else
                {
                    brightestLightIndex = brightestSpotLightIndex = spotLightIndices[1] + hasMainLight;
                }
            }

            // Replace with the brighest spot light
            if (useBrighestLight && brightestSpotLightIndex >= 0)
            {
                var brightestSpotLightColor = visibleLights[brightestSpotLightIndex].light.color * visibleLights[brightestSpotLightIndex].light.intensity;
                var brightestSpotLightStrength = brightestSpotLightColor.r * 0.299f + brightestSpotLightColor.g * 0.587f + brightestSpotLightColor.b * 0.114f;
                brightestLightIndex = (hasMainLight == 1 && mainLightStrength >= brightestSpotLightStrength) ? renderingData.lightData.mainLightIndex : brightestSpotLightIndex;
            }

            // Update Light Camera transform (Main or Brighest light)
            if (brightestLightIndex >= 0 && brightestLightIndex < visibleLights.Length)
            {
                CharShadowCamera.Instance.SetLightCameraTransform(visibleLights[brightestLightIndex].light);
                brightestLightDirection = -visibleLights[brightestLightIndex].light.transform.forward;
            }

            // Send to GPU
            cmd.SetGlobalVector(s_BrightestLightDirection, brightestLightDirection);
            cmd.SetGlobalInt(s_CharShadowLocalLightIndex, brightestSpotLightIndex >= 0 ? brightestSpotLightIndex - hasMainLight : -1);
        }

        ///<returns>
        /// [0]: FollowLight, [1]: Additional SpotLight
        ///</returns>
        private static List<int> CalculateMostIntensiveLightIndices(ref RenderingData renderingData, LayerMask followLayer)
        {
            if (CharShadowCamera.Instance == null || CharShadowCamera.Instance.activeTarget == null)
            {
                return null;
            }

            var lightCount = renderingData.lightData.visibleLights.Length;
            var lightOffset = 0;
            while (lightOffset < lightCount && renderingData.lightData.visibleLights[lightOffset].lightType == LightType.Directional)
            {
                lightOffset++;
            }
            lightCount -= lightOffset;
            var directionalLightCount = lightOffset;
            if (renderingData.lightData.mainLightIndex != -1 && directionalLightCount != 0) directionalLightCount -= 1;
            var visibleLights = renderingData.lightData.visibleLights.GetSubArray(lightOffset, lightCount);

            s_vSpotLights.Clear();
            s_vSpotLightIndices.Clear();
            s_SortedSpotLights.Clear();
            
            // Extract spot lights
            for (int i = 0; i < visibleLights.Length; i++)
            {
                if (visibleLights[i].lightType == LightType.Spot)
                {
                    s_vSpotLightIndices.Add(i + directionalLightCount);
                    s_vSpotLights.Add(visibleLights[i]);
                }
            }

            // Calculate light intensity
            var target = CharShadowCamera.Instance.activeTarget;
            for (int i = 0; i < s_vSpotLights.Count; i++)
            {
                var light = s_vSpotLights[i].light;
                var diff = target.position - light.transform.position;
                var dirToTarget = Vector3.Normalize(diff);
                var L = light.transform.rotation * Vector3.forward;
                var dotL = Vector3.Dot(dirToTarget, L);
                var distance = diff.magnitude;
                var cos = Mathf.Cos(light.spotAngle * Mathf.Deg2Rad);
                if (dotL <= cos || distance > light.range)
                {
                    continue;
                }

                var finalColor = s_vSpotLights[i].finalColor;
                var atten = 1f - distance / light.range;
                var strength = (finalColor.r * 0.229f + finalColor.g * 0.587f + finalColor.b * 0.114f) * atten * cos;
                if (strength > 0.01f)
                {
                    s_SortedSpotLights.Add(new KeyValuePair<float, int>(strength, s_vSpotLightIndices[i]));
                }
            }
            // Sort
            s_SortedSpotLights.Sort((x, y) => y.Key.CompareTo(x.Key));

            var charSpotLightIndices = new List<int>(2) { -1, -1 };
            int followLightLayer = (int)Mathf.Log(followLayer.value, 2);
            for (int i = 0; i < s_SortedSpotLights.Count; i++)
            {
                var curr = s_SortedSpotLights[i].Value;
                if (visibleLights[curr].light.gameObject.layer == followLightLayer)
                {
                    if (charSpotLightIndices[0] < 0)
                        charSpotLightIndices[0] = curr;
                }
                else
                {
                    if (charSpotLightIndices[1] < 0)
                        charSpotLightIndices[1] = curr;
                }
            }

            return charSpotLightIndices;
        }
    }
}
