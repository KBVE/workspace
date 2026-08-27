import { useEffect, useRef } from 'react';
import { installGodotBridge } from './bridge';
import {
  boot,
  logEngine,
  useBoot,
  useProgress,
  useBootError,
  useLoading,
  useRun,
} from '../state/gameStore';
import { RunState } from './state';
import { useView } from '../state/paperStore';
import { useFrameStyle } from '../paper/frame';


function loadEngineScript(source: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const alreadyLoaded = document.querySelector(`script[data-godot="${source}"]`);
    if (alreadyLoaded) {
      resolve();
      return;
    }
    const scriptElement = document.createElement('script');
    scriptElement.src = source;
    scriptElement.async = true;
    scriptElement.dataset.godot = source;
    scriptElement.onload = () => resolve();
    scriptElement.onerror = () => reject(new Error(`failed to load ${source}`));
    document.body.appendChild(scriptElement);
  });
}


const injectedGlobals = window as unknown as {
  __godotConfig?: Record<string, unknown>;
  __godotLoader?: string;
};

const ENGINE_LOADER_SOURCE = injectedGlobals.__godotLoader ?? 'godot/index.js';

const FALLBACK_CONFIG = {
  executable: 'godot/index',
  mainPack: 'godot/index.pck',
  canvasResizePolicy: 2,
  ensureCrossOriginIsolationHeaders: true,
  experimentalVK: false,
  focusCanvas: true,
  gdextensionLibs: [],
  emscriptenPoolSize: 8,
  godotPoolSize: 4,
  args: [],
} as const;

const ENGINE_CONFIG = injectedGlobals.__godotConfig ?? FALLBACK_CONFIG;

export function GodotGame() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const hasStartedRef = useRef(false);

  useEffect(() => {
    if (hasStartedRef.current) return;
    hasStartedRef.current = true;
    boot.start();

    installGodotBridge();

    loadEngineScript(ENGINE_LOADER_SOURCE)
      .then(async () => {
        const EngineConstructor = window.Engine;
        if (!EngineConstructor) {
          throw new Error('Godot loader did not attach window.Engine');
        }

        const missingFeatures = EngineConstructor.getMissingFeatures?.({ ...ENGINE_CONFIG }) ?? [];
        if (missingFeatures.length > 0) {
          throw new Error(
            `Browser is missing required features: ${missingFeatures.join(', ')}`,
          );
        }

        const engine = new EngineConstructor({ ...ENGINE_CONFIG });
        await engine.startGame({
          canvas: canvasRef.current!,
          onProgress: (loadedBytes: number, totalBytes: number) => {
            boot.progress(
              totalBytes > 0 ? Math.round((loadedBytes / totalBytes) * 100) : null,
            );
          },
          onPrintError: (...messageParts: unknown[]) => {
            const engineLine = messageParts.join(' ');
            logEngine(engineLine);
            if (engineLine.includes('Blocking on the main thread')) console.trace(engineLine);
            else console.error(...messageParts);
          },
        });
        boot.running();
      })
      .catch((reason: unknown) =>
        boot.fail(reason instanceof Error ? reason.message : String(reason)),
      );
  }, []);

  return <GodotLayer canvasRef={canvasRef} />;
}

function GodotLayer({ canvasRef }: { canvasRef: React.RefObject<HTMLCanvasElement | null> }) {
  const view = useView();
  const layerRef = useRef<HTMLDivElement>(null);
  const style = useFrameStyle(layerRef);

  return (
    <div
      ref={layerRef}
      className={`godot-layer${view === 'paper' ? ' is-plate' : ''}`}
      style={style}
    >
      <canvas ref={canvasRef} id="godot-canvas" />
      <div className="halftone" aria-hidden />
      <BootCurtain />
    </div>
  );
}

function BootCurtain() {
  const bootPhase = useBoot();
  const bootProgress = useProgress();
  const bootError = useBootError();
  const sceneLoading = useLoading();
  const run = useRun();

  const engineReady = bootPhase === 'running';
  const sceneLive = run !== RunState.BOOTING;
  const failed = bootPhase === 'failed' || sceneLoading?.status === 'failed';

  const liftedOnce = useRef(false);
  if (sceneLive && !failed) liftedOnce.current = true;
  const lifted = liftedOnce.current;

  if (failed) {
    return (
      <div className="godot-curtain is-error" role="alert">
        <p className="curtain-kicker">The presses have jammed</p>
        <pre className="curtain-detail">
          {bootError ?? `Could not load ${sceneLoading?.scene ?? 'the scene'}`}
        </pre>
      </div>
    );
  }

  const percent = engineReady
    ? sceneLoading
      ? Math.round(sceneLoading.progress * 100)
      : null
    : bootProgress;
  const caption = engineReady ? 'Inking the plate' : 'Setting the presses';
  const known = percent !== null;

  return (
    <div
      className={`godot-curtain${lifted ? ' is-lifted' : ''}`}
      aria-hidden={lifted}
      aria-busy={!lifted}
      data-testid="boot-curtain"
    >
      <p className="curtain-kicker">{caption}</p>
      <div className={`curtain-rule${known ? '' : ' is-indeterminate'}`} aria-hidden>
        <span style={known ? { width: `${Math.max(2, Math.min(100, percent))}%` } : undefined} />
      </div>
      <p className="curtain-percent" data-testid="boot-curtain-percent">
        {known ? `${percent}%` : 'Please wait'}
      </p>
    </div>
  );
}
