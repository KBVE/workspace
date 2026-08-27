import { describePlayerFlags } from '../godot/state';
import { useFlags, usePlayer } from '../state/gameStore';
import { useDispatches, useRunningOrder } from '../state/paperStore';
import { carriedItems, listedAs, passengers, plateCopy, standing } from '../content/content';
import { openResearch } from '../state/researchStore';
import { eidOf } from '../research/world';
import styles from './paper.module.css';

function runningOrderMark(
  runningOrder: ReturnType<typeof useRunningOrder>,
  levelIndex: number,
): string {
  if (!runningOrder) return 'awaiting';
  if (runningOrder.index === levelIndex) {
    return runningOrder.outcome === 'lost' ? 'lost' : 'in progress';
  }
  return levelIndex < runningOrder.index ? 'settled' : 'to come';
}

export function Sidebar() {
  const player = usePlayer();
  const flags = useFlags();
  const runningOrder = useRunningOrder();

  return (
    <aside className={styles.sidebar}>
      <Section title="The Weather">
        <p className={styles.tight}>{standing.weather}</p>
      </Section>

      <Section title="Condition of Our Correspondent">
        <dl className={styles.ledger}>
          <div>
            <dt>Constitution</dt>
            <dd>{player ? `${player.health} of ${player.max_health}` : 'Not yet aboard'}</dd>
          </div>
          <div>
            <dt>Disposition</dt>
            <dd>{describePlayerFlags(flags).toLowerCase()}</dd>
          </div>
        </dl>
      </Section>

      <Section title="The Running Order">
        <dl className={styles.ledger} data-testid="running-order">
          {standing.runningOrder.map((levelName, levelIndex) => (
            <div key={levelName}>
              <dt>{levelName}</dt>
              <dd>{runningOrderMark(runningOrder, levelIndex)}</dd>
            </div>
          ))}
        </dl>
      </Section>

      <Section title="Passenger List">
        <ul className={styles.list}>
          {passengers.map((passenger) => (
            <li key={passenger.id}>
              <button
                className={styles.nameLink}
                onClick={() => openResearch(eidOf(passenger.id))}
              >
                {listedAs(passenger)}
              </button>
              {passenger.suspect && (
                <span className={styles.mark} title="Under enquiry"> †</span>
              )}
            </li>
          ))}
        </ul>
        <button
          className={styles.boardLink}
          onClick={() => openResearch()}
          data-testid="open-dossier"
        >
          Consult the case board
        </button>
      </Section>

      <Section title="Personal Effects">
        <p className={styles.tight}>
          {carriedItems()
            .map((item) => item.name)
            .join(' · ')}
        </p>
      </Section>

      <Section title="Notices &amp; Appointments">
        <dl className={styles.ledger}>
          {standing.notices.map(([notice, appointment]) => (
            <div key={notice}>
              <dt>{notice}</dt>
              <dd>{appointment}</dd>
            </div>
          ))}
        </dl>
      </Section>
    </aside>
  );
}

export function PlateRail() {
  const player = usePlayer();
  const flags = useFlags();
  const runningOrder = useRunningOrder();

  return (
    <aside className={styles.rail} data-testid="plate-rail">
      <p className={styles.railCondition}>
        <span className={styles.railConditionLabel}>Condition</span>
        <span className={styles.railStat}>
          {player ? `${player.health}/${player.max_health}` : '—'}
        </span>
        <span className={styles.railNote}>{describePlayerFlags(flags).toLowerCase()}</span>
      </p>

      <h3 className={styles.railHead}>Weather</h3>
      <p className={styles.railWeather}>{standing.weather}</p>

      <h3 className={styles.railHead}>Order</h3>
      <ol className={styles.railOrder}>
        {standing.runningOrder.map((levelName, levelIndex) => (
          <li key={levelName} data-mark={runningOrderMark(runningOrder, levelIndex)}>
            {levelName}
          </li>
        ))}
      </ol>

      <h3 className={styles.railHead}>Passengers</h3>
      <ul className={styles.railPeople} data-testid="rail-passengers">
        {passengers.map((passenger) => (
          <li key={passenger.id}>
            <button
              className={styles.railName}
              onClick={() => openResearch(eidOf(passenger.id))}
            >
              {listedAs(passenger)}
            </button>
            {passenger.suspect && <span className={styles.mark}> †</span>}
          </li>
        ))}
      </ul>

      <h3 className={styles.railHead}>Effects</h3>
      <p className={styles.railWeather}>
        {carriedItems()
          .map((item) => item.name)
          .join(' · ')}
      </p>

      <h3 className={styles.railHead}>Notices</h3>
      <dl className={styles.railNotices}>
        {standing.notices.map(([notice, appointment]) => (
          <div key={notice}>
            <dt>{notice}</dt>
            <dd>{appointment}</dd>
          </div>
        ))}
      </dl>

      <button
        className={styles.railBoard}
        onClick={() => openResearch()}
        data-testid="rail-dossier"
      >
        Case board
      </button>
    </aside>
  );
}

export function Telegrams() {
  const dispatches = useDispatches();

  return (
    <section className={styles.telegrams}>
      <h3 className={styles.sectionHead}>Telegrams &amp; Dispatches</h3>
      <ul className={styles.wire} data-testid="paper-dispatches">
        {dispatches.map((dispatch) => (
          <li key={dispatch.id}>
            <span className={styles.wireLabel}>{dispatch.label}</span>
            {dispatch.text}
          </li>
        ))}
        {dispatches.length === 0 && <li className={styles.quiet}>{plateCopy.quiet}</li>}
      </ul>
    </section>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className={styles.block}>
      <h3 className={styles.sectionHead}>{title}</h3>
      {children}
    </section>
  );
}
