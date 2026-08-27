import { useEffect, useState } from 'react';

/**
 * Frames per second, sampled from the browser's own callback rather than from
 * Godot. The engine used to print this into a Label inside the 3D scene, which
 * cost a string build every frame; this measures the same thing from outside.
 *
 * Only mount it while the panel is open, or it keeps a rAF loop alive forever.
 */
export function useFrameRate(sampleMs = 500): number | null {
  const [framesPerSecond, setFramesPerSecond] = useState<number | null>(null);

  useEffect(() => {
    let handle = 0;
    let frames = 0;
    let windowStart = performance.now();

    const tick = () => {
      frames += 1;
      const elapsed = performance.now() - windowStart;
      if (elapsed >= sampleMs) {
        setFramesPerSecond(Math.round((frames / elapsed) * 1000));
        frames = 0;
        windowStart = performance.now();
      }
      handle = requestAnimationFrame(tick);
    };

    handle = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(handle);
  }, [sampleMs]);

  return framesPerSecond;
}

export interface CanvasResolution {
  width: number;
  height: number;
  devicePixelRatio: number;
}

/**
 * The size Godot is actually rendering, which is the canvas backing store and
 * not its CSS box. Worth watching directly: it is what every framerate decision
 * in this project has turned on, and nothing else on the page reveals it.
 */
export function useCanvasResolution(pollMs = 1000): CanvasResolution | null {
  const [resolution, setResolution] = useState<CanvasResolution | null>(null);

  useEffect(() => {
    const read = () => {
      const canvas = document.querySelector<HTMLCanvasElement>('#godot-canvas');
      if (!canvas || canvas.width === 0) return;
      setResolution((previous) =>
        previous && previous.width === canvas.width && previous.height === canvas.height
          ? previous
          : { width: canvas.width, height: canvas.height, devicePixelRatio },
      );
    };
    read();
    const timer = window.setInterval(read, pollMs);
    return () => window.clearInterval(timer);
  }, [pollMs]);

  return resolution;
}
