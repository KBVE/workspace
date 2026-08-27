import { Aperture, X, Trash2 } from 'lucide-react';
import { clearTrace, toggleDebug } from '../state/gameStore';
import styles from './debug.module.css';

export function DebugHeader() {
  return (
    <header className={styles.head}>
      <Aperture size={14} strokeWidth={2} aria-hidden />
      <strong>game state</strong>
      <button onClick={clearTrace} aria-label="Clear event trace" data-testid="debug-clear">
        <Trash2 size={13} aria-hidden />
      </button>
      <button onClick={toggleDebug} aria-label="Close debug panel" data-testid="debug-close">
        <X size={14} aria-hidden />
      </button>
    </header>
  );
}
