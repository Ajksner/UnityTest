Shader "Custom/GrayscaleWithNormalMapAndMetallic"
{
    Properties
    {
        _MainTex ("Base (RGB)", 2D) = "white" { }
        _NormalMap ("Normal Map", 2D) = "bump" { }
        _MetallicTex ("Metallic Map", 2D) = "white" { }
        _SmoothnessMap ("Smoothness Map", 2D) = "white" { }
        _Metallic ("Metallic Intensity", Range(0,1)) = 1.0
        _Smoothness ("Smoothness Intensity", Range(0,1)) = 0.5
        _Saturation ("Saturation", Range(0, 1)) = 0.5
        _Contrast ("Contrast", Range(0, 2)) = 1.0
        _Tiling ("Tiling", Vector) = (1, 1, 0, 0)
        _AOTex ("Ambient Occlusion Map", 2D) = "white" { }
        _Brightness ("Brightness", Range(0, 2)) = 1.0
        _GrayScaleFactor ("Grayscale Gamma", Range(0.2, 5)) = 1.0
        _SpecularIntensity ("Specular Intensity", Range(0, 5)) = 1.0
        _AmbientIntensity ("Ambient Intensity", Range(0, 3)) = 1.0
        _ShadowsIntensity ("Shadows Intensity", Range(0, 1)) = 0.7
        _FresnelPower ("Fresnel Power", Range(0, 10)) = 5.0   // Nový parametr pro sílu Fresnel efektu
        _FresnelIntensity ("Fresnel Intensity", Range(0, 2)) = 1.0   // Nový parametr pro intenzitu Fresnel efektu
        _FresnelColor ("Fresnel Color", Color) = (1,1,1,1)    // Nový parametr pro barvu Fresnel efektu
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            // Input structures
            struct appdata_t
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float3 worldNormal : TEXCOORD2;
                float3 worldTangent : TEXCOORD3;
                float3 worldBitangent : TEXCOORD4;
            };

            // Textures and parameters
            sampler2D _MainTex;
            sampler2D _NormalMap;
            sampler2D _MetallicTex;
            sampler2D _SmoothnessMap;
            sampler2D _AOTex;
            float _Metallic;
            float _Smoothness;
            float _Saturation;
            float _Contrast;
            float4 _Tiling;
            float _Brightness;
            float _GrayScaleFactor;
            float _SpecularIntensity;
            float _AmbientIntensity;
            float _ShadowsIntensity;
            float _FresnelPower;     // Nový parametr
            float _FresnelIntensity; // Nový parametr
            float4 _FresnelColor;    // Nový parametr

            v2f vert(appdata_t v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv * _Tiling.xy + _Tiling.zw;
                
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                
                o.worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
                o.worldBitangent = cross(o.worldNormal, o.worldTangent) * v.tangent.w;
                
                return o;
            }

            // Helper functions
            half3 AdjustContrast(half3 color, float contrast)
            {
                return saturate((color - 0.5) * contrast + 0.5);
            }

            half3 ApplyGammaCorrection(half3 color, float gamma)
            {
                return pow(color, gamma);
            }

            float GGXDistribution(float NdotH, float roughness)
            {
                float alpha = roughness * roughness;
                float alpha2 = alpha * alpha;
                float denom = (NdotH * NdotH * (alpha2 - 1.0) + 1.0);
                return alpha2 / (UNITY_PI * denom * denom);
            }

            float GeometrySmithGGX(float NdotL, float NdotV, float roughness)
            {
                float r = roughness + 1.0;
                float k = (r * r) / 8.0;
                float GL = NdotL / (NdotL * (1.0 - k) + k);
                float GV = NdotV / (NdotV * (1.0 - k) + k);
                return GL * GV;
            }

            float3 FresnelSchlick(float cosTheta, float3 F0)
            {
                return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
            }

            // Samostatná funkce pro výpočet Fresnel efektu s nastavitelnou silou
            float3 CalculateCustomFresnel(float3 normal, float3 viewDir, float3 fresnelColor, float power, float intensity)
            {
                float fresnelFactor = pow(1.0 - max(dot(normal, viewDir), 0.0), power);
                return fresnelColor * fresnelFactor * intensity;
            }

            float3 CalculateIBL(float3 normal, float3 viewDir, float3 albedo, float roughness, float metallic)
            {
                // Jednoduchá aproximace IBL založená na normálách
                float3 ambientColor = lerp(unity_AmbientSky.rgb, unity_AmbientEquator.rgb, 
                    normal.y * 0.5 + 0.5);
                
                // Přidáme vliv metalličnosti a roughness na ambient
                float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
                float3 F = F0 + (max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0) - F0) * 
                    pow(1.0 - max(dot(normal, viewDir), 0.0), 5.0);
                
                float3 kD = (1.0 - F) * (1.0 - metallic);
                
                // Difuzní a spekulární složka ambientu
                float3 diffuseIBL = kD * albedo * ambientColor;
                float3 specularIBL = F * ambientColor * (1.0 - roughness);
                
                return diffuseIBL + specularIBL;
            }

            half3 CalculatePBRLighting(half3 albedo, half3 normal, half3 worldPos, half metallic, half smoothness, half ao)
            {
                // Konvertujeme smoothness na roughness
                float roughness = 1.0 - smoothness;
                float roughness2 = roughness * roughness;
                
                // Směr pohledu a světla
                float3 viewDir = normalize(_WorldSpaceCameraPos - worldPos);
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                float3 halfDir = normalize(lightDir + viewDir);
                
                // Důležité dot produkty
                float NdotL = max(dot(normal, lightDir), 0.001);
                float NdotV = max(dot(normal, viewDir), 0.001);
                float NdotH = max(dot(normal, halfDir), 0.001);
                float VdotH = max(dot(viewDir, halfDir), 0.001);
                
                // Základní odrazivost
                float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
                
                // Cook-Torrance BRDF
                float D = GGXDistribution(NdotH, roughness);
                float G = GeometrySmithGGX(NdotL, NdotV, roughness);
                float3 F = FresnelSchlick(VdotH, F0);
                
                // Spekulární a difuzní složka
                float3 specularTerm = (D * G * F) / (4.0 * NdotL * NdotV + 0.001);
                specularTerm *= _SpecularIntensity;
                
                // Kovy nemají difuzní složku
                float3 kD = (1.0 - F) * (1.0 - metallic);
                float3 diffuse = kD * albedo / UNITY_PI;
                
                // Změkčení stínů - upravíme NdotL pro méně ostré stíny
                float shadowedNdotL = pow(NdotL, _ShadowsIntensity);
                
                // Přímé osvětlení s barvou světla
                float3 directLighting = (diffuse + specularTerm) * _LightColor0.rgb * shadowedNdotL;
                
                // Vylepšené ambient osvětlení s IBL
                float3 iblLighting = CalculateIBL(normal, viewDir, albedo, roughness, metallic);
                float3 ambient = albedo * ao * unity_AmbientSky.rgb * _AmbientIntensity;
                
                // Přidáme IBL k základnímu ambientu
                ambient = lerp(ambient, iblLighting * _AmbientIntensity, 0.6) * ao;
                
                // Výpočet vlastního Fresnel efektu
                float3 fresnel = CalculateCustomFresnel(normal, viewDir, _FresnelColor.rgb, _FresnelPower, _FresnelIntensity);
                
                // Celkové osvětlení s přidaným Fresnel efektem
                return ambient + directLighting + fresnel;
            }

            half4 frag(v2f i) : SV_Target
            {
                // Sample textures
                half4 baseColor = tex2D(_MainTex, i.uv);
                half3 normalMap = UnpackNormal(tex2D(_NormalMap, i.uv));
                half metallicValue = tex2D(_MetallicTex, i.uv).r * _Metallic;
                half smoothnessValue = tex2D(_SmoothnessMap, i.uv).r * _Smoothness;
                half aoValue = tex2D(_AOTex, i.uv).r;

                // Apply grayscale effect with gamma
                half gray = dot(baseColor.rgb, half3(0.299, 0.587, 0.114));
                half correctedGray = pow(gray, _GrayScaleFactor);
                baseColor.rgb = lerp(half3(correctedGray, correctedGray, correctedGray), baseColor.rgb, _Saturation);
                
                // Apply contrast and brightness
                baseColor.rgb = AdjustContrast(baseColor.rgb, _Contrast) * _Brightness;
                
                // Transform normal from tangent to world space
                float3x3 tangentToWorld = float3x3(
                    normalize(i.worldTangent),
                    normalize(i.worldBitangent),
                    normalize(i.worldNormal)
                );
                half3 worldNormal = mul(normalMap, tangentToWorld);
                worldNormal = normalize(worldNormal);
                
                // Calculate lighting with the metallic and smoothness values
                half3 finalColor = CalculatePBRLighting(
                    baseColor.rgb,
                    worldNormal,
                    i.worldPos,
                    metallicValue,
                    smoothnessValue,
                    aoValue
                );

                // Možnost zobrazit pouze Fresnel efekt pro účely ladění
                // Odkomentujte následující řádek pro zobrazení pouze Fresnel efektu
                // float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
                // return half4(CalculateCustomFresnel(worldNormal, viewDir, _FresnelColor.rgb, _FresnelPower, _FresnelIntensity), 1.0);
                
                // Přidáme minimální osvětlení, aby nic nebylo úplně černé
                finalColor = max(finalColor, 0.05 * baseColor.rgb);
                
                return half4(finalColor, baseColor.a);
            }
            ENDCG
        }
    }
    FallBack "Standard"
}