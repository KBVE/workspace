import { useEngineLog } from '../state/gameStore';
import styles from './debug.module.css';

export function EngineErrors() {
  const engineLog = useEngineLog();
  if (engineLog.length === 0) return null;

  const errorCount = engineLog.filter((line) => line.level === 'error').length;

  return (
    <>
      <div className={styles.sectionHead}>
        engine log
        <span>
          {errorCount} err / {engineLog.length - errorCount} warn
        </span>
      </div>
      <ol className={`${styles.list} ${styles.errors}`} data-testid="engine-errors">
        {engineLog.map((line) => (
          <li key={line.id} data-level={line.level}>
            <span className={line.level === 'warn' ? styles.warn : undefined}>{line.text}</span>
          </li>
        ))}
      </ol>
    </>
  );
}
