import * as THREE from 'three';
import { shaderMaterial } from '@react-three/drei';
import { extend, type ThreeElement } from '@react-three/fiber';
import {
	DERIVE_TANGENT,
	HEIGHT_HELPERS,
	POM_MARCH,
	POM_VARYINGS,
	SPOM_SILHOUETTE,
} from './pom.glsl';
import { POM_DEFAULTS } from './uniforms';

export const POM_SOURCE_BRICK = 0;
export const POM_SOURCE_LUMA = 1;
export const POM_SOURCE_MAP = 2;

const vertex = /* glsl */ `
	${POM_VARYINGS}
	${DERIVE_TANGENT}

	void main() {
		vec3 worldPos = (modelMatrix * vec4(position, 1.0)).xyz;
		vec3 worldNormal = mat3(modelMatrix) * normal;
		pomDeriveTangent(worldNormal, worldPos, cameraPosition, uv);
		gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
	}
`;

const fragment = /* glsl */ `
	${POM_VARYINGS}

	uniform sampler2D uAlbedo;
	uniform sampler2D uHeightMap;
	uniform int uSource;
	uniform vec2 uBricks;
	uniform float uMortar;
	uniform float uPomScale;
	uniform float uMinLayers;
	uniform float uMaxLayers;
	uniform float uSilhouette;
	uniform vec4 uBounds;

	${HEIGHT_HELPERS}

	float pomSampleDepth(vec2 uv) {
		if (uSource == ${POM_SOURCE_BRICK}) return pomDepthBrick(uv, uBricks, uMortar);
		if (uSource == ${POM_SOURCE_LUMA}) return pomDepthFromLuma(uAlbedo, uv);
		return 1.0 - texture2D(uHeightMap, uv).r;
	}

	${POM_MARCH}
	${SPOM_SILHOUETTE}

	void main() {
		float hitDepth;
		vec2 uv = pomMarch(
			vPomUv, vPomViewTS, uPomScale, uMinLayers, uMaxLayers, hitDepth
		);
		if (uSilhouette > 0.5 && pomSilhouetteClip(uv, uBounds)) discard;

		vec3 col = uSource == ${POM_SOURCE_BRICK}
			? vec3(0.72, 0.68, 0.62)
			: texture2D(uAlbedo, uv).rgb;
		float shade = 1.0 - hitDepth * 0.6;
		gl_FragColor = vec4(col * shade, 1.0);
	}
`;

const PomMaterialBase = shaderMaterial(
	{
		uAlbedo: null as THREE.Texture | null,
		uHeightMap: null as THREE.Texture | null,
		uSource: POM_SOURCE_BRICK,
		uBricks: new THREE.Vector2(4, 8),
		uMortar: 0.06,
		uPomScale: POM_DEFAULTS.scale,
		uMinLayers: POM_DEFAULTS.minLayers,
		uMaxLayers: POM_DEFAULTS.maxLayers,
		uSilhouette: 0,
		uBounds: new THREE.Vector4(0, 0, 1, 1),
	},
	vertex,
	fragment,
);

let registered = false;

/**
 * Registers `<pomMaterial>` in react-three-fiber's element catalogue.
 *
 * Called once when this module is first evaluated, which is how the tag has
 * always come to exist. It is exported and made idempotent because that import
 * side effect is the package's only one, and it is invisible to a bundler: the
 * r3f entry point re-exports constants and types from here and nothing that
 * references the material itself, so a build told the package is side-effect
 * free may drop this call and leave `<pomMaterial>` silently unknown at render
 * time. A consumer in that position can call this to put it back.
 *
 * This is why package.json carries no `sideEffects: false`, and
 * PomMaterial.spec.tsx fails if one is added.
 */
export function registerPomMaterial(): void {
	if (registered) return;
	registered = true;
	extend({ PomMaterial: PomMaterialBase });
}

registerPomMaterial();

export type PomMaterialType = THREE.ShaderMaterial & {
	uAlbedo: THREE.Texture | null;
	uHeightMap: THREE.Texture | null;
	uSource: number;
	uPomScale: number;
};

declare module '@react-three/fiber' {
	interface ThreeElements {
		pomMaterial: ThreeElement<typeof PomMaterialBase>;
	}
}
