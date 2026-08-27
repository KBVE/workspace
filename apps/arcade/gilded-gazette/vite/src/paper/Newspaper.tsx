import { LeadStory } from './LeadStory';
import { Masthead } from './Masthead';
import { Plate } from './Plate';
import { PlateRail, Sidebar, Telegrams } from './Sidebar';
import { useView } from '../state/paperStore';
import styles from './paper.module.css';


export function Newspaper() {
  const view = useView();

  return (
    <div
      className={`${styles.sheet}${view === 'paper' ? ` ${styles.open}` : ''}`}
      aria-hidden={view !== 'paper'}
      data-testid="newspaper"
      data-view={view}
    >
      <Masthead />
      <div className={styles.body}>
        <div className={styles.main}>
          <Plate />
          <PlateRail />
          <LeadStory />
        </div>
        <Sidebar />
      </div>
      <Telegrams />
    </div>
  );
}
