import Phaser from 'phaser';

/** Quick hit-flash: white fill, settle to a hit colour, then clear. */
export function flashEntity(
	scene: Phaser.Scene,
	sprite: Phaser.GameObjects.Sprite,
	hitColor = 0xff6b6b,
): void {
	// The flash runs for 180ms after a hit, and a hit is the likeliest thing to
	// destroy the sprite before it ends. A destroyed GameObject has had its
	// internals torn down, so tinting one throws from inside a timer callback,
	// where the stack says nothing about what caused it.
	const alive = () => sprite.active && sprite.scene;

	sprite.setTint(0xffffff).setTintMode(Phaser.TintModes.FILL);
	scene.time.delayedCall(60, () => {
		if (alive()) sprite.setTint(hitColor);
	});
	scene.time.delayedCall(180, () => {
		if (!alive()) return;
		sprite.clearTint();
		sprite.setTintMode(Phaser.TintModes.MULTIPLY);
	});
}

/** Rising, fading combat/emote text that destroys itself when done. */
export function floatingText(
	scene: Phaser.Scene,
	x: number,
	y: number,
	text: string,
	color: string,
	depth: number,
): Phaser.GameObjects.Text {
	const label = scene.add
		.text(x, y, text, {
			fontFamily: 'monospace',
			fontSize: '14px',
			color,
			stroke: '#000000',
			strokeThickness: 3,
		})
		.setOrigin(0.5, 1)
		.setDepth(depth);
	scene.tweens.add({
		targets: label,
		y: y - 28,
		alpha: 0,
		duration: 900,
		ease: 'Cubic.easeOut',
		onComplete: () => label.destroy(),
	});
	return label;
}

/** Draw a health bar into an existing graphics object (green→amber→red). */
export function drawHealthBar(
	g: Phaser.GameObjects.Graphics,
	centerX: number,
	topY: number,
	hp: number,
	maxHp: number,
	width = 26,
): void {
	// maxHp of 0 makes hp/maxHp NaN, and NaN passes through both clamps
	// untouched -- Math.min and Math.max return it as-is -- so the fill width
	// would reach fillRect as NaN and the bar would render as garbage. An
	// entity with no max health is not exotic; it is one not yet given stats.
	const pct = maxHp > 0 ? Math.max(0, Math.min(1, hp / maxHp)) : 0;
	g.clear();
	g.fillStyle(0x000000, 0.6);
	g.fillRect(centerX - width / 2, topY, width, 4);
	g.fillStyle(pct > 0.5 ? 0x4ade80 : pct > 0.25 ? 0xfbbf24 : 0xf87171, 1);
	g.fillRect(centerX - width / 2 + 0.5, topY + 0.5, (width - 1) * pct, 3);
}

/**
 * Draw a health bar only if hp/maxHp changed since last draw (cache on lastHp).
 * Returns true if drawn, false if skipped.
 */
export function drawHealthBarCached(
	g: Phaser.GameObjects.Graphics,
	centerX: number,
	topY: number,
	hp: number,
	maxHp: number,
	lastHp: { hp: number; maxHp: number } | undefined,
	width = 26,
): { drawn: boolean; cache: { hp: number; maxHp: number } } {
	// Follow every frame via the Graphics transform (cheap) so the bar tracks a
	// moving entity even when hp is unchanged; the hp-cache gates only the fill
	// redraw, which is drawn at local origin so setPosition alone places it.
	g.setPosition(centerX, topY);
	if (lastHp && lastHp.hp === hp && lastHp.maxHp === maxHp) {
		return { drawn: false, cache: lastHp };
	}
	drawHealthBar(g, 0, 0, hp, maxHp, width);
	return { drawn: true, cache: { hp, maxHp } };
}

export interface CameraZoomOptions {
	min?: number;
	max?: number;
	step?: number;
}

/**
 * Wire +/- keys and the mouse wheel to clamped main-camera zoom.
 *
 * Returns a disposer. A scene that restarts calls this again, and the input
 * plugin outlives the scene's create(), so without one every restart leaves
 * another set of handlers attached and one keypress zooms by the number of
 * restarts so far.
 */
export function attachCameraZoom(
	scene: Phaser.Scene,
	{ min = 0.6, max = 2.2, step = 0.2 }: CameraZoomOptions = {},
): () => void {
	const zoom = (delta: number) => {
		const cam = scene.cameras.main;
		cam.setZoom(Phaser.Math.Clamp(cam.zoom + delta, min, max));
	};
	const zoomIn = () => zoom(step);
	const zoomOut = () => zoom(-step);
	const wheel = (_p: unknown, _o: unknown, _dx: number, dy: number) =>
		zoom(dy > 0 ? -step * 0.75 : step * 0.75);

	scene.input.keyboard?.on('keydown-PLUS', zoomIn);
	scene.input.keyboard?.on('keydown-MINUS', zoomOut);
	scene.input.on('wheel', wheel);

	return () => {
		scene.input.keyboard?.off('keydown-PLUS', zoomIn);
		scene.input.keyboard?.off('keydown-MINUS', zoomOut);
		scene.input.off('wheel', wheel);
	};
}
