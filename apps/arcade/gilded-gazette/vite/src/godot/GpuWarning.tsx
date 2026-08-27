import { useEffect, useState } from 'react';
import { inspectGpu, type GpuReport } from './gpu';
import styles from './gpu.module.css';

/** Dismissed for this tab only: a new tab is a new machine as far as this can tell. */
const DISMISSED = 'gazette:gpu-warning-dismissed';

/**
 * Says so when the browser is drawing the train on the CPU.
 *
 * Not a boot failure, so not the curtain: the game runs, badly, and the player is
 * entitled to decide whether to sit through it. Shown once per tab and dismissible.
 */
export function GpuWarning() {
  const [report, setReport] = useState<GpuReport | null>(null);

  useEffect(() => {
    let dismissed = false;
    try {
      dismissed = sessionStorage.getItem(DISMISSED) === '1';
    } catch {
      /* private windows throw on access; treat that as not dismissed */
    }
    if (dismissed) return;
    const found = inspectGpu();
    if (found.verdict !== 'accelerated') setReport(found);
  }, []);

  if (!report) return null;

  const missing = report.verdict === 'missing';

  const dismiss = () => {
    try {
      sessionStorage.setItem(DISMISSED, '1');
    } catch {
      /* nothing to remember it with; the warning simply returns next reload */
    }
    setReport(null);
  };

  return (
    <>
      <div className={styles.scrim} aria-hidden />
      <div className={styles.sheet} role="alertdialog" aria-labelledby="gpu-warning-title">
        <p className={styles.kicker}>Notice to the reader</p>
        <h2 className={styles.title} id="gpu-warning-title">
          {missing ? 'This browser has no WebGL' : 'Hardware acceleration is off'}
        </h2>
        <p className={styles.body}>
          {missing
            ? 'The train is drawn with WebGL, and this browser is not offering it. The'
              + ' game will not start until it is enabled.'
            : 'Your browser is drawing the train on the processor instead of the graphics'
              + ' card. It will run, but at a few frames a second, and that is the setting'
              + ' rather than the game.'}
        </p>
        <ul className={styles.fixes}>
          <li>Chrome and Edge: Settings, System, use graphics acceleration when available.</li>
          <li>Firefox: Settings, General, Performance, use recommended settings.</li>
          <li>Safari: Develop menu, make sure WebGL is not disabled.</li>
          <li>Then reload this page.</li>
        </ul>
        {report.renderer && (
          <p className={styles.renderer}>Reported renderer: {report.renderer}</p>
        )}
        <button className={styles.dismiss} onClick={dismiss} data-testid="gpu-warning-dismiss">
          {missing ? 'Continue anyway' : 'Read on regardless'}
        </button>
      </div>
    </>
  );
}
