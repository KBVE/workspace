import { closeNotice, useReading } from '../state/noticeStore';
import { sectionOf } from '../content/content';
import styles from './notice.module.css';

/**
 * The sheet a poster in the carriage opens.
 *
 * The image is the notice; everything under it is what the player has worked out
 * about it, which is why the sections are printed as the paper would print them and
 * not as a tooltip. Only what Godot sent crosses -- the id -- so this reads the same
 * compiled notice the engine hung on the wall.
 */
export function Notice() {
  const notice = useReading();

  return (
    <>
      <div
        className={`${styles.scrim}${notice ? ` ${styles.shown}` : ''}`}
        onClick={closeNotice}
        aria-hidden
      />
      <div
        className={`${styles.sheet}${notice ? ` ${styles.shown}` : ''}`}
        aria-hidden={!notice}
        aria-label={notice?.title}
        role="dialog"
        data-testid="notice"
      >
        {notice && (
          <>
            <button className={styles.close} onClick={closeNotice} aria-label="Put the notice back">
              &times;
            </button>
            <img className={styles.plate} src={`/notices/${notice.id}.png`} alt={notice.title} />
            <p className={styles.lede}>{notice.lede}</p>
            {['the_rule', 'the_clauses', 'what_nobody_says'].map((key) => {
              const section = sectionOf(notice, key);
              if (!section) return null;
              return (
                <section className={styles.block} key={key}>
                  <h3 className={styles.heading}>{section.heading}</h3>
                  {section.paragraphs.map((p) => (
                    <p className={styles.body} key={p}>
                      {p}
                    </p>
                  ))}
                  {section.bullets.length > 0 && (
                    <ul className={styles.clauses}>
                      {section.bullets.map((b) => (
                        <li key={b}>{b}</li>
                      ))}
                    </ul>
                  )}
                </section>
              );
            })}
          </>
        )}
      </div>
    </>
  );
}
