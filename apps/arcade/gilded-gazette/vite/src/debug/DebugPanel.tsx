import { Aperture } from 'lucide-react';
import { toggleDebug, useDebugOpen } from '../state/gameStore';
import { DebugHeader } from './DebugHeader';
import { DebugState } from './DebugState';
import { EngineErrors } from './EngineErrors';
import { EventTrace } from './EventTrace';
import { JournalLog } from './JournalLog';
import styles from './debug.module.css';

export function DebugPanel() {
  const open = useDebugOpen();

  return (
    <>
      <button
        className={`${styles.toggle}${open ? ` ${styles.open}` : ''}`}
        onClick={toggleDebug}
        aria-label={open ? 'Hide debug panel' : 'Open debug panel'}
        aria-expanded={open}
        data-testid="debug-toggle"
      >
        <Aperture size={20} strokeWidth={1.75} aria-hidden />
      </button>
      {open && <DebugBody />}
    </>
  );
}

function DebugBody() {
  return (
    <div className={styles.panel} role="dialog" aria-label="Game state" data-testid="debug-panel">
      <DebugHeader />
      <DebugState />
      <EngineErrors />
      <JournalLog />
      <EventTrace />
    </div>
  );
}
