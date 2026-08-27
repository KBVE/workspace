import { useEffect } from 'react';
import { GodotGame } from './godot/GodotGame';
import { GpuWarning } from './godot/GpuWarning';
import { DebugPanel } from './debug/DebugPanel';
import { Newspaper } from './paper/Newspaper';
import { Dossier } from './paper/Dossier';
import { Notice } from './paper/Notice';
import { setView, toggleView, useView } from './state/paperStore';
import { closeResearch, useResearchStore } from './state/researchStore';
import { closeNotice, useNoticeStore } from './state/noticeStore';
import {
  useBridgeReady,
  usePlaying,
  usePaused,
  usePlayer,
  useSend,
  useInvulnerable,
} from './state/gameStore';

function PlayerHud() {
  const player = usePlayer();
  const paused = usePaused();
  const invulnerable = useInvulnerable();
  const send = useSend();

  return (
    <div className="hud">
      {player && (
        <span className={invulnerable ? 'hud-invuln' : undefined}>
          HP {player.health} / {player.max_health}
        </span>
      )}
      <button onClick={() => send('ui:pause', { paused: !paused })}>
        {paused ? 'Resume' : 'Pause'}
      </button>
      <button onClick={() => setView('paper')} data-testid="open-paper">
        Read the Gazette
      </button>
      <button onClick={() => send('ui:restart', {})} data-testid="restart">
        Restart
      </button>
      <button onClick={() => send('ui:main_menu', {})} data-testid="main-menu">
        Leave Train
      </button>
    </div>
  );
}

function useEscapeKeyLayering() {
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      if (useNoticeStore.getState().reading) {
        closeNotice();
        return;
      }
      if (useResearchStore.getState().open) {
        closeResearch();
        return;
      }
      toggleView();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);
}

export default function App() {
  const bridgeReady = useBridgeReady();
  const playing = usePlaying();
  const view = useView();

  useEscapeKeyLayering();

  return (
    <div className="app" data-view={view}>
      <Newspaper />
      <GodotGame />
      <div className="ui-layer">
        {bridgeReady && playing && view === 'world' && <PlayerHud />}
        <DebugPanel />
      </div>
      <Dossier />
      <Notice />
      <GpuWarning />
    </div>
  );
}
