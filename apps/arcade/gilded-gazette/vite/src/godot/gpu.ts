/**
 * Whether the browser is drawing this with a GPU or with the CPU pretending to be one.
 *
 * A software rasteriser does not fail: it runs, at a handful of frames a second, and
 * the player concludes the game is broken rather than that their browser is. Asking
 * once at boot and saying so is cheaper than every one of them filing that report.
 */

/** Renderer strings the software rasterisers report themselves under. */
const SOFTWARE = /swiftshader|llvmpipe|softpipe|software|basic render|generic renderer/i;

export type GpuVerdict = 'accelerated' | 'software' | 'missing';

export interface GpuReport {
  verdict: GpuVerdict;
  /** What the driver called itself, when it was willing to say. */
  renderer: string;
}

export function inspectGpu(): GpuReport {
  let canvas: HTMLCanvasElement;
  try {
    canvas = document.createElement('canvas');
  } catch {
    return { verdict: 'missing', renderer: '' };
  }

  const gl =
    (canvas.getContext('webgl2') as WebGL2RenderingContext | null) ??
    (canvas.getContext('webgl') as WebGLRenderingContext | null);
  if (!gl) return { verdict: 'missing', renderer: '' };

  // &unmasked -> RENDERER alone is masked to a generic string in most browsers now;
  //              the debug extension is what still names the actual device, and it is
  //              absent exactly where privacy settings hide it, not where the GPU is
  const debug = gl.getExtension('WEBGL_debug_renderer_info');
  const renderer = String(
    (debug && gl.getParameter(debug.UNMASKED_RENDERER_WEBGL)) || gl.getParameter(gl.RENDERER) || '',
  );

  // a masked renderer is not evidence of software; only a named rasteriser is
  return { verdict: SOFTWARE.test(renderer) ? 'software' : 'accelerated', renderer };
}
