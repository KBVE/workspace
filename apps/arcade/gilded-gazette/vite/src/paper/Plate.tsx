import { usePlaying } from '../state/gameStore';
import { useEdition, setView } from '../state/paperStore';
import { plateCopy } from '../content/content';
import { usePlateMeasure } from './frame';
import styles from './paper.module.css';

export function Plate() {
  const ref = usePlateMeasure<HTMLButtonElement>();
  const edition = useEdition();
  const playing = usePlaying();

  return (
    <figure className={styles.plate}>
      <button
        ref={ref}
        className={styles.plateHole}
        onClick={() => setView('world')}
        aria-label="Return to the scene"
        data-testid="paper-plate"
      />
      <figcaption className={styles.caption}>
        {edition?.caption}
        {playing && <span className={styles.board}> — {plateCopy.board}</span>}
      </figcaption>
    </figure>
  );
}
