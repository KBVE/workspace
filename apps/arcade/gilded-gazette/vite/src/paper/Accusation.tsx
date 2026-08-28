import { useSend } from '../state/gameStore';
import { useRunningOrder } from '../state/paperStore';
import { useVictim } from '../state/researchStore';
import {
  forgetNaming,
  name,
  useNaming,
  useNamingIsWhole,
} from '../state/notebookStore';
import { showVerdict, useVerdict } from '../state/verdictStore';
import { rooms, suspects, weapons, type Answer } from './answers';
import styles from './dossier.module.css';

/**
 * The run's one irreversible move.
 *
 * Three parts or none of it. A name alone was the accusation while the weapon and the
 * room were not things a reader could have worked out; the weapon is drawn now and
 * left lying in the room it was used in, so finding it answers two thirds at once,
 * which is what makes asking for the last third fair rather than a lottery.
 *
 * Separate from the notebook above it, though it offers the same three lists. The
 * sheet is what the reader believes and nothing checks it; this is what they are
 * prepared to be wrong about in front of the answer.
 */
export function Accusation() {
  const send = useSend();
  const victim = useVictim();
  const order = useRunningOrder();
  const naming = useNaming();
  const whole = useNamingIsWhole();
  const verdict = useVerdict();

  // One accusation, once. The run is over the moment it is given, and a second would
  // talk a wrong answer into a right one with nothing recording the reader had been
  // wrong -- the engine refuses it too, and this is so the button does not lie.
  const settled = order ? order.outcome !== 'start' : false;

  return (
    <section className={styles.block} data-testid="accusation">
      <h3 className={styles.head2}>The Accusation</h3>

      <Part
        part="who"
        label="Who"
        options={suspects(victim)}
        chosen={naming.who}
        disabled={settled}
      />
      <Part
        part="weapon"
        label="With what"
        options={weapons()}
        chosen={naming.weapon}
        disabled={settled}
      />
      <Part
        part="room"
        label="Where"
        options={rooms()}
        chosen={naming.room}
        disabled={settled}
      />

      <button
        className={styles.name}
        data-testid="accuse"
        disabled={!whole || settled}
        title={
          settled
            ? 'The enquiry is closed.'
            : whole
              ? 'Say it, and be told'
              : 'An accusation names somebody, something and somewhere.'
        }
        onClick={() => {
          send('ui:accuse', { who: naming.who, weapon: naming.weapon, room: naming.room });
          forgetNaming();
        }}
      >
        Name them
      </button>

      {!settled && (
        <p className={styles.hint}>
          {whole
            ? 'There is no taking it back, and no second one.'
            : 'All three, or it is not an accusation.'}
        </p>
      )}
      {settled && (
        <p className={styles.hint} data-testid="accusation-closed">
          The enquiry is closed.{' '}
          {verdict && (
            <button
              className={styles.link}
              data-testid="reopen-verdict"
              onClick={showVerdict}
            >
              Read the verdict again.
            </button>
          )}
        </p>
      )}
    </section>
  );
}

function Part({
  part,
  label,
  options,
  chosen,
  disabled,
}: {
  part: 'who' | 'weapon' | 'room';
  label: string;
  options: Answer[];
  chosen: string;
  disabled: boolean;
}) {
  return (
    <label className={styles.namingRow}>
      <span className={styles.namingLabel}>{label}</span>
      <select
        className={styles.namingPick}
        data-testid={`accuse-${part}`}
        value={chosen}
        disabled={disabled}
        onChange={(event) => name(part, event.target.value === chosen ? '' : event.target.value)}
      >
        <option value="">&mdash;</option>
        {options.map((option) => (
          <option key={option.id} value={option.id}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  );
}
