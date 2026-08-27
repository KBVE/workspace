import { runStateName, describePlayerFlags, worldModeName } from '../godot/state';
import {
  useBoot,
  useProgress,
  useBootError,
  useBridgeReady,
  useRun,
  useFlags,
  useWorld,
  usePlayer,
  useViewer,
  useRenderBudget,
  useDoor,
  useLevel,
} from '../state/gameStore';
import { useClock } from '../state/paperStore';
import { Row } from './Row';
import { useCanvasResolution, useFrameRate } from './useFrameRate';
import styles from './debug.module.css';

const clockText = (minutes: number | null) =>
  minutes === null
    ? 'not ticked'
    : `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;

export function DebugState() {
  const boot = useBoot();
  const progress = useProgress();
  const error = useBootError();
  const bridgeReady = useBridgeReady();
  const run = useRun();
  const flags = useFlags();
  const world = useWorld();
  const player = usePlayer();
  const viewer = useViewer();
  const renderBudget = useRenderBudget();
  const door = useDoor();
  const level = useLevel();
  const clock = useClock();
  const fps = useFrameRate();
  const resolution = useCanvasResolution();

  return (
    <section className={styles.grid}>
      <Row label="fps" value={fps === null ? 'sampling' : String(fps)} />
      <Row
        label="render"
        value={
          resolution
            ? `${resolution.width}x${resolution.height} @${resolution.devicePixelRatio}x`
            : 'unknown'
        }
      />
      <Row
        label="scale"
        value={renderBudget ? renderBudget.detail : 'not reported'}
      />
      <Row label="boot" value={boot === 'loading' ? `loading ${progress}%` : boot} />
      <Row label="bridge" value={bridgeReady ? 'ready' : 'waiting'} />
      <Row label="run" value={`${runStateName(run)} (${run})`} />
      <Row label="flags" value={`${describePlayerFlags(flags)} (0x${flags.toString(16)})`} />
      <Row label="world" value={worldModeName(world)} />
      <Row label="player" value={player ? `hp ${player.health}/${player.max_health}` : 'none'} />
      <Row
        label="where"
        value={viewer ? `carriage ${viewer.carriage} — ${viewer.location || 'nowhere'}` : 'unknown'}
      />
      <Row
        label="door"
        value={
          door
            ? `${door.locked ? 'locked' : door.open ? 'open' : 'shut'} at ${door.distance}m`
            : 'untouched'
        }
      />
      <Row label="clock" value={clockText(clock)} />
      <Row
        label="chapter"
        value={level ? `${level.level} ${level.index + 1}/${level.total} — ${level.outcome}` : 'none'}
      />
      {error && <Row label="error" value={error} />}
    </section>
  );
}
