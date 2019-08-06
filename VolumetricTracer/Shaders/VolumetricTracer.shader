Shader "FX/VolumetricTracer"
{
	Properties
	{
		_MainTex ("Gradient", 2D) = "white" {}
		_Color ("Color", Color) = (1, 1, 1, 1)
		_Intensity ("Intensity", Float) = 4
		_SoftBlend ("Soft Blend", Range(0.001, 10)) = 0.5
	}
	SubShader
	{
		Pass
		{
			Tags { "RenderType"="Transparent" "Queue"="Transparent" }
			Blend SrcAlpha OneMinusSrcAlpha
			ZWrite Off
			ZTest Always
			Cull Front

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_instancing

			#include "UnityCG.cginc"

			struct v2f
			{
				float4 vertex 		: SV_POSITION;
				float2 texcoord		: TEXCOORD0;
				float3 worldPos		: TEXCOORD1;
				float3 localPos		: TEXCOORD2;
				float4 screenPos	: TEXCOORD3;
				float3 localCamera	: TEXCOORD4;

				UNITY_VERTEX_INPUT_INSTANCE_ID
				UNITY_VERTEX_OUTPUT_STEREO
			};

			sampler2D 	_MainTex;
			float4		_Color;
			float		_Intensity;
			float		_SoftBlend;

			v2f vert (appdata_full v)
			{
				UNITY_SETUP_INSTANCE_ID(v);
				v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);
				UNITY_TRANSFER_INSTANCE_ID(v, o);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

				o.vertex 		= UnityObjectToClipPos(v.vertex);
				// Prevent mesh from being clipped by near clip plane
				o.vertex.z 		= min(o.vertex.z, 0);
				o.worldPos 		= mul(unity_ObjectToWorld, v.vertex);
				o.localPos 		= v.vertex.xyz;
				o.texcoord 		= v.texcoord;
				o.screenPos		= ComputeScreenPos(o.vertex);
				o.localCamera	= mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz;

				return o;
			}

			// Ray-sphere intersection. Returns the distance to the first and second intersection along the ray (or -1 if ray misses)
			float2 RaySphereIntersection (float3 ro, float3 rd, float3 sc, float sr)
			{
				ro -= sc;
				float a = dot(rd, rd);
				float b = 2.0 * dot(ro, rd);
				float c = dot(ro, ro) - (sr * sr);
				float d = b * b - 4 * a * c;
				if (d < 0)
				{
					return -1;
				}
				else
				{
					d = sqrt(d);
					return float2(-b - d, -b + d) / (2 * a);
				}
			}

			sampler2D _CameraDepthTexture;

			fixed4 frag (v2f i) : SV_Target
			{
				UNITY_SETUP_INSTANCE_ID(i);

				float2 screenUV = i.screenPos.xy / i.screenPos.w;
				float3 viewDir = normalize(i.worldPos - _WorldSpaceCameraPos);
				// Linear eye depth
				float  sceneDepth = LinearEyeDepth(tex2D(_CameraDepthTexture, screenUV));
				// Linear eye depth -> world space distance
				float3 camFwd = UNITY_MATRIX_V[2].xyz;
				float  sceneDistance = sceneDepth / dot(-viewDir, camFwd);
				// Scene world-space position
				float3 scenePos = _WorldSpaceCameraPos + viewDir * sceneDistance;

				fixed4 color = 0;

				float3 rd = mul(unity_WorldToObject, float4(viewDir, 0));
				float3 ro = i.localCamera;

				float2 sphere = RaySphereIntersection(ro, rd, float3(0, 0, 0), 0.5);

				if (sphere.x > 0 || sphere.y > 0)
				{
					sphere.x = max(sphere.x, 0);

					// World-space entry point. Used for scene blending
					float3 entry = mul(unity_ObjectToWorld, float4(ro + rd * sphere.x, 1));

					float3 mid = ro + rd * (sphere.x + sphere.y) * 0.5;

					float alpha = 1 - length(mid) / 0.5;

					color.rgb = tex2D(_MainTex, float2(alpha, 0.5)) * _Intensity;
					color.a = smoothstep(0, 1, alpha);

					// Scene blending
					color.a *= saturate((sceneDistance - length(entry - _WorldSpaceCameraPos)) / _SoftBlend);
				}

				color *= _Color;
				
				return color;
			}
			ENDCG
		}
	}
}