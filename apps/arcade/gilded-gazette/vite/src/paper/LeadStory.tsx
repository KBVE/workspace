import { useEdition } from '../state/paperStore';
import styles from './paper.module.css';

export function LeadStory() {
  const edition = useEdition();
  if (!edition) return null;

  return (
    <article className={styles.lead}>
      <p className={styles.kicker}>{edition.kicker}</p>
      <h2 className={styles.headline} data-testid="paper-headline">
        {edition.title}
      </h2>
      <div className={styles.columns}>
        <p className={styles.dropCap}>{edition.lede}</p>
        {edition.body.map((para) => (
          <p key={para.slice(0, 32)}>{para}</p>
        ))}
      </div>
    </article>
  );
}
