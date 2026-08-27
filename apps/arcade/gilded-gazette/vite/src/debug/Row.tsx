import styles from './debug.module.css';

export function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className={styles.row} data-testid={`row-${label}`}>
      <span className={styles.key}>{label}</span>
      <span className={styles.val} data-testid="row-value">
        {value}
      </span>
    </div>
  );
}
