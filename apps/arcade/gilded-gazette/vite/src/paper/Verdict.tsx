import { useSend } from '../state/gameStore';
import { openResearch } from '../state/researchStore';
import {
  hideVerdict,
  useVerdict,
  useVerdictShown,
  wasRight,
  type Verdict as TheVerdict,
} from '../state/verdictStore';
import { passengers, type LocationId } from '../content/content';
import { nameOf } from './answers';
import styles from './verdict.module.css';

/**
 * What happened, once it no longer matters that the reader knows.
 *
 * Clue ends by opening the envelope, and it opens it whether or not the accusation was
 * right: a mystery that keeps its answer from somebody who has already lost is not
 * being mysterious, it is refusing to finish. So this prints all three parts either
 * way, and marks which of them the reader had.
 *
 * The engine sends the answer at this one moment and never before, so there is nothing
 * to guard here -- by the time the store has a verdict the run is over.
 */
export function Verdict() {
  const verdict = useVerdict();
  const shown = useVerdictShown();

  return (
    <>
      <div
        className={`${styles.scrim}${shown ? ` ${styles.shown}` : ''}`}
        onClick={hideVerdict}
        aria-hidden
      />
      <div
        className={`${styles.sheet}${shown ? ` ${styles.shown}` : ''}`}
        aria-hidden={!shown}
        role="dialog"
        aria-label="The verdict"
        data-testid="verdict"
      >
        {verdict && <Sheet verdict={verdict} />}
      </div>
    </>
  );
}

function Sheet({ verdict }: { verdict: TheVerdict }) {
  const send = useSend();
  const right = wasRight(verdict);

  return (
    <>
      <p className={styles.kicker}>The Envelope</p>
      <h2
        className={`${styles.title} ${right ? styles.right : styles.wrong}`}
        data-testid="verdict-outcome"
        data-outcome={right ? 'won' : 'lost'}
      >
        {right ? 'You had them.' : 'You had the wrong end of it.'}
      </h2>
      <p className={styles.lede}>
        {right
          ? 'Every part of it, and the train pulls in with the thing settled.'
          : 'The accusation is given and there is no taking it back. This is what happened.'}
      </p>

      <div className={styles.rows} data-testid="verdict-rows">
        <Row label="Who" part="who" truth={verdict.who} said={verdict.namedWho} />
        <Row label="With" part="weapon" truth={verdict.weapon} said={verdict.namedWeapon} />
        <Row label="Where" part="room" truth={verdict.room} said={verdict.namedRoom} />
      </div>

      <Deed who={verdict.who} room={verdict.room} />

      <div className={styles.buttons}>
        <button
          className={styles.again}
          data-testid="verdict-again"
          onClick={() => send('ui:restart', {})}
        >
          Another night
        </button>
        <button
          className={styles.aside}
          data-testid="verdict-board"
          onClick={() => {
            hideVerdict();
            openResearch();
          }}
        >
          Back to the board
        </button>
      </div>
    </>
  );
}

/**
 * One third of the answer, and the reader's third beside it when the two differ.
 * When they agree there is nothing to print twice.
 */
function Row({
  label,
  part,
  truth,
  said,
}: {
  label: string;
  part: 'who' | 'weapon' | 'room';
  truth: string;
  said: string;
}) {
  const had = truth === said;

  return (
    <div className={styles.row} data-testid={`verdict-${part}`} data-had={had ? 'yes' : 'no'}>
      <span className={styles.label}>{label}</span>
      <span className={styles.truth}>
        {nameOf(part, truth)}
        {!had && <span className={styles.said}>you said {nameOf(part, said) || 'nothing'}</span>}
      </span>
      <span
        className={`${styles.tick} ${had ? styles.right : styles.wrong}`}
        title={had ? 'You had this' : 'You did not have this'}
      >
        {had ? '✓' : '✗'}
      </span>
    </div>
  );
}

/**
 * The culprit, in the room it happened in, in the words the content already has for
 * finding them there. Authored rather than composed: a generated night still has to
 * read like somebody wrote it, and a sentence assembled out of three ids never does.
 */
function Deed({ who, room }: { who: string; room: string }) {
  const culprit = passengers.find((p) => p.id === who);
  const seen = culprit?.sightings[room as LocationId]?.[0];

  if (!seen) return null;

  return (
    <p className={styles.deed} data-testid="verdict-deed">
      {seen}
    </p>
  );
}
