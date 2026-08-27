import { vi } from 'vitest';

// Phaser probes canvas support the moment the module is imported -- it fills a
// pixel and reads it back to decide whether inverse-alpha compositing works.
// jsdom's getContext() returns null, so the import itself throws before any
// test runs. This is the smallest 2D context that answers that probe; nothing
// here is a general-purpose canvas, and a test that needs real drawing should
// pull in the `canvas` package instead.
const context = {
	fillStyle: '',
	globalCompositeOperation: '',
	fillRect: vi.fn(),
	clearRect: vi.fn(),
	getImageData: (_x: number, _y: number, w: number, h: number) => ({
		data: new Uint8ClampedArray(w * h * 4),
		width: w,
		height: h,
	}),
	putImageData: vi.fn(),
	drawImage: vi.fn(),
	getContextAttributes: () => ({ alpha: true }),
};

HTMLCanvasElement.prototype.getContext = vi.fn(
	() => context,
) as unknown as HTMLCanvasElement['getContext'];
