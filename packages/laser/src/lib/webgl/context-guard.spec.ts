import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
	installWebGLContextGuard,
	isWebGLAvailable,
	reportWebGLEvent,
} from './context-guard';

describe('isWebGLAvailable', () => {
	afterEach(() => vi.unstubAllGlobals());

	const stubCanvas = (getContext: () => unknown) => {
		vi.stubGlobal('window', { ...globalThis.window, WebGLRenderingContext: class {} });
		vi.spyOn(document, 'createElement').mockReturnValue({
			getContext,
		} as unknown as HTMLElement);
	};

	it('is false where there is no window at all', () => {
		vi.stubGlobal('window', undefined);
		expect(isWebGLAvailable()).toBe(false);
	});

	// An old browser exposes window but no WebGL constructor.
	it('is false when the browser has no WebGL constructor', () => {
		vi.stubGlobal('window', {});
		expect(isWebGLAvailable()).toBe(false);
	});

	it('is false when a context cannot be created', () => {
		stubCanvas(() => null);
		expect(isWebGLAvailable()).toBe(false);
	});

	it('is true on webgl2', () => {
		const gl = { getExtension: vi.fn(() => null) };
		stubCanvas(() => gl);
		expect(isWebGLAvailable()).toBe(true);
	});

	// The probe releases the context it just took. A browser allows only a
	// handful at once, so leaving this one open costs the app a real canvas.
	it('releases the probe context when it can', () => {
		const loseContext = vi.fn();
		const gl = { getExtension: vi.fn(() => ({ loseContext })) };
		stubCanvas(() => gl);

		expect(isWebGLAvailable()).toBe(true);
		expect(gl.getExtension).toHaveBeenCalledWith('WEBGL_lose_context');
		expect(loseContext).toHaveBeenCalled();
	});

	// Some environments throw from getContext rather than returning null.
	it('is false when the probe throws', () => {
		stubCanvas(() => {
			throw new Error('blocked');
		});
		expect(isWebGLAvailable()).toBe(false);
	});
});

describe('reportWebGLEvent', () => {
	let dispatch: ReturnType<typeof vi.fn>;

	beforeEach(() => {
		dispatch = vi.fn();
		vi.stubGlobal('window', {
			...globalThis.window,
			dispatchEvent: dispatch,
			CustomEvent: globalThis.CustomEvent,
		});
		vi.spyOn(console, 'warn').mockImplementation(() => {});
		vi.spyOn(console, 'info').mockImplementation(() => {});
	});

	afterEach(() => {
		vi.unstubAllGlobals();
		vi.restoreAllMocks();
	});

	it('warns for a loss and informs for a restore', () => {
		reportWebGLEvent('lost');
		expect(console.warn).toHaveBeenCalled();

		reportWebGLEvent('restored');
		expect(console.info).toHaveBeenCalled();
	});

	it('publishes the event for a host that is listening', () => {
		reportWebGLEvent('unsupported', { reason: 'no gpu' });

		const event = dispatch.mock.calls[0][0] as CustomEvent;
		expect(event.type).toBe('kbve:webgl');
		expect(event.detail).toEqual({ kind: 'unsupported', reason: 'no gpu' });
	});

	// Telemetry is best-effort: a host that cannot take the event must not turn
	// a context loss into a second, unrelated failure.
	it('survives a dispatch that throws', () => {
		dispatch.mockImplementation(() => {
			throw new Error('detached');
		});
		expect(() => reportWebGLEvent('lost')).not.toThrow();
	});
});

describe('installWebGLContextGuard', () => {
	const makeCanvas = () => {
		const listeners = new Map<string, EventListener>();
		return {
			listeners,
			addEventListener: vi.fn((type: string, fn: EventListener) =>
				listeners.set(type, fn),
			),
			removeEventListener: vi.fn((type: string) => listeners.delete(type)),
		};
	};

	beforeEach(() => {
		vi.spyOn(console, 'warn').mockImplementation(() => {});
		vi.spyOn(console, 'info').mockImplementation(() => {});
	});

	afterEach(() => vi.restoreAllMocks());

	it('calls back on loss and on restore', () => {
		const canvas = makeCanvas();
		const onLost = vi.fn();
		const onRestored = vi.fn();
		installWebGLContextGuard(canvas as never, { onLost, onRestored });

		const event = { preventDefault: vi.fn() };
		canvas.listeners.get('webglcontextlost')!(event as never);
		expect(onLost).toHaveBeenCalled();

		canvas.listeners.get('webglcontextrestored')!({} as never);
		expect(onRestored).toHaveBeenCalled();
	});

	// The browser only fires webglcontextrestored if the loss event was
	// cancelled. Without preventDefault the context is gone for good.
	it('cancels the loss event so a restore can follow', () => {
		const canvas = makeCanvas();
		installWebGLContextGuard(canvas as never, {
			onLost: vi.fn(),
			onRestored: vi.fn(),
		});

		const event = { preventDefault: vi.fn() };
		canvas.listeners.get('webglcontextlost')!(event as never);
		expect(event.preventDefault).toHaveBeenCalled();
	});

	it('returns a disposer that removes both listeners', () => {
		const canvas = makeCanvas();
		const dispose = installWebGLContextGuard(canvas as never, {
			onLost: vi.fn(),
			onRestored: vi.fn(),
		});

		dispose();
		expect(canvas.removeEventListener).toHaveBeenCalledTimes(2);
		expect(canvas.listeners.size).toBe(0);
	});
});
