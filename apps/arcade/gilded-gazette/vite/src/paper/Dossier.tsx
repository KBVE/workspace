import { useRef } from 'react';
import { journalKindName } from '../godot/state';
import { roomName } from '../content/content';
import {
  closeResearch,
  setAt,
  setFocus,
  useAt,
  useFocus,
  useFrom,
  useResearchOpen,
  useTo,
} from '../state/researchStore';
import { useMoment, useRecord } from '../research/useResearch';
import {
  clockOf,
  effectsOf,
  factsAbout,
  isSuspect,
  labels,
  roomOf,
  roster,
  LOCATION_IDS,
  Source,
  tiesOf,
  trailOf,
  whoIsAt,
  allFacts,
  type FactRow,
  type Placement,
} from '../research/world';
import styles from './dossier.module.css';

export function Dossier() {
  const open = useResearchOpen();

  const hasEverOpened = useRef(false);
  if (open) hasEverOpened.current = true;

  return (
    <>
      <div
        className={`${styles.scrim}${open ? ` ${styles.shown}` : ''}`}
        onClick={closeResearch}
        aria-hidden
      />
      <aside
        className={`${styles.drawer}${open ? ` ${styles.shown}` : ''}`}
        aria-hidden={!open}
        aria-label="Case board"
        data-testid="dossier"
      >
        <header className={styles.head}>
          <h2 className={styles.title}>The Case Board</h2>
          <button className={styles.close} onClick={closeResearch} aria-label="Close the case board">
            &times;
          </button>
        </header>

        {hasEverOpened.current && <Board />}
      </aside>
    </>
  );
}

function Board() {
  const focus = useFocus();

  return (
    <>
      <Scrubber />
      <div className={styles.scroll}>
        <Manifest focus={focus} />
        {focus ? (
          <Person eid={focus} />
        ) : (
          <>
            <Rooms />
            <Ledger />
          </>
        )}
      </div>
    </>
  );
}

function Scrubber() {
  const boardMinute = useAt();
  const earliestMinute = useFrom();
  const latestMinute = useTo();

  return (
    <div className={styles.scrubber}>
      <div className={styles.scrubRow}>
        <span className={styles.head2}>As of</span>
        <span className={styles.clock} data-testid="dossier-clock">
          {clockOf(boardMinute)}
        </span>
      </div>
      <input
        className={styles.slider}
        type="range"
        min={earliestMinute}
        max={latestMinute}
        step={5}
        value={boardMinute}
        onChange={(event) => setAt(Number(event.target.value))}
        aria-label="Hour of the enquiry"
        data-testid="dossier-scrub"
      />
      <div className={styles.scrubEnds}>
        <span>{clockOf(earliestMinute)}</span>
        <span>{clockOf(latestMinute)}</span>
      </div>
    </div>
  );
}

function Manifest({ focus }: { focus: number }) {
  const manifest = useRecord(() =>
    roster().map((passengerEid) => ({
      passengerEid,
      name: labels[passengerEid],
      suspect: isSuspect(passengerEid),
    })),
  );
  const currentRooms = useMoment(
    () => manifest.map((passenger) => roomOf(passenger.passengerEid)),
    [manifest],
  );

  return (
    <section className={styles.block}>
      <h3 className={styles.head2}>Manifest</h3>
      <ul className={styles.people} data-testid="dossier-manifest">
        {manifest.map((passenger, rowIndex) => (
          <li key={passenger.passengerEid}>
            <button
              className={`${styles.person}${
                focus === passenger.passengerEid ? ` ${styles.picked}` : ''
              }`}
              onClick={() => setFocus(passenger.passengerEid)}
              aria-pressed={focus === passenger.passengerEid}
            >
              <span className={styles.personName}>
                {passenger.name}
                {passenger.suspect && (
                  <span className={styles.mark} title="Under enquiry"> †</span>
                )}
              </span>
              <span className={styles.personWhere}>
                {currentRooms[rowIndex] ? roomName(currentRooms[rowIndex]!) : '—'}
              </span>
            </button>
          </li>
        ))}
      </ul>
      {focus === 0 && (
        <p className={styles.hint}>Choose a name to read their movements.</p>
      )}
    </section>
  );
}

function Rooms() {
  const occupancy = useMoment(() =>
    LOCATION_IDS.map((location) => ({
      location,
      occupants: whoIsAt(location).map((passengerEid) => labels[passengerEid]),
    })),
  );

  return (
    <section className={styles.block}>
      <h3 className={styles.head2}>The Train, At That Hour</h3>
      <dl className={styles.ledger} data-testid="dossier-rooms">
        {occupancy.map((room) => (
          <div key={room.location}>
            <dt>{roomName(room.location)}</dt>
            <dd>
              {room.occupants.length ? (
                room.occupants.join(', ')
              ) : (
                <span className={styles.quiet}>empty</span>
              )}
            </dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function Person({ eid: passengerEid }: { eid: number }) {
  const movements = useRecord(() => trailOf(passengerEid), [passengerEid]);
  const connections = useRecord(() => tiesOf(passengerEid), [passengerEid]);
  const personalEffects = useRecord(
    () => effectsOf(passengerEid).map((itemEid) => labels[itemEid]),
    [passengerEid],
  );
  const recordedFacts = useRecord(() => factsAbout(passengerEid), [passengerEid]);

  return (
    <>
      <section className={styles.block}>
        <h3 className={styles.head2}>Movements &mdash; {labels[passengerEid]}</h3>
        <Trail steps={movements} />
      </section>

      {connections.length > 0 && (
        <section className={styles.block}>
          <h3 className={styles.head2}>Connections</h3>
          <ul className={styles.list}>
            {connections.map((connection) => (
              <li key={connection.other}>
                <button
                  className={styles.link}
                  onClick={() => setFocus(connection.other)}
                >
                  {labels[connection.other]}
                </button>
                {connection.tie && (
                  <span className={styles.tie}> — {connection.tie}</span>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {personalEffects.length > 0 && (
        <section className={styles.block}>
          <h3 className={styles.head2}>Effects</h3>
          <p className={styles.tight}>{personalEffects.join(' · ')}</p>
        </section>
      )}

      <Facts facts={recordedFacts} title="On the Record" />
    </>
  );
}

function Trail({ steps }: { steps: Placement[] }) {
  const boardMinute = useAt();

  if (steps.length === 0) {
    return (
      <ol className={styles.trail} data-testid="dossier-trail">
        <li className={styles.quiet}>No movements recorded.</li>
      </ol>
    );
  }

  return (
    <ol className={styles.trail} data-testid="dossier-trail">
      {steps.map((step, stepIndex) => {
        const wasObserved = step.source === Source.JOURNAL;
        return (
          <li
            key={`${step.at}-${stepIndex}`}
            className={step.at > boardMinute ? styles.ahead : undefined}
            data-source={wasObserved ? 'seen' : 'claimed'}
          >
            <span className={styles.when}>{clockOf(step.at)}</span>
            <span className={styles.wherePart}>{roomName(step.location)}</span>
            <span
              className={styles.proof}
              title={wasObserved ? 'Observed' : 'Claimed'}
            >
              {wasObserved ? '●' : '○'}
            </span>
          </li>
        );
      })}
    </ol>
  );
}

function Facts({ facts, title }: { facts: FactRow[]; title: string }) {
  if (facts.length === 0) {
    return (
      <section className={styles.block}>
        <h3 className={styles.head2}>{title}</h3>
        <p className={styles.quiet}>Nothing yet.</p>
      </section>
    );
  }

  return (
    <section className={styles.block}>
      <h3 className={styles.head2}>{title}</h3>
      <ul className={styles.list} data-testid="dossier-facts">
        {facts.map((fact) => (
          <li key={fact.eid}>
            <span className={styles.when}>{clockOf(fact.at)}</span>{' '}
            <span className={styles.kind}>
              {journalKindName(fact.kind).toLowerCase()}
            </span>{' '}
            {fact.actor ? labels[fact.actor] : ''}
            {fact.target ? ` → ${labels[fact.target]}` : ''}
            {fact.place ? ` (${roomName(fact.place)})` : ''}
          </li>
        ))}
      </ul>
    </section>
  );
}

export function Ledger() {
  const everyFact = useRecord(() => allFacts());
  return <Facts facts={everyFact} title="The Record" />;
}
