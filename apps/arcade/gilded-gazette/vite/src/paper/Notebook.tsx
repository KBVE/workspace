import {
  items,
  locations,
  listedAs,
  passengers,
  type Item,
  type LocationId,
} from '../content/content';
import { useVictim } from '../state/researchStore';
import {
  clearMarks,
  cycleMark,
  markKey,
  useMark,
  useMarkedCount,
  type Mark,
} from '../state/notebookStore';
import styles from './dossier.module.css';

/**
 * The three questions an accusation answers, and every answer the run could give
 * to each. Read off the content rather than written down here: a passenger added
 * to shared/data appears on the sheet without this file knowing they exist, and a
 * sheet that had to be kept in step by hand would be one edit from lying.
 */
interface Column {
  key: string;
  title: string;
  rows: { id: string; label: string }[];
  /** Said when the column has nothing in it worth ruling out. */
  thin?: string;
}

/**
 * Everybody aboard who is not the body, which is exactly the set TheNight draws its
 * culprit from. Who the body is is drawn per run and arrives on the wire, so this
 * takes it as an argument rather than reading a flag that no longer exists -- and
 * before the enquiry opens it lists everybody, which is the honest answer for the
 * half second before the engine has said.
 */
const suspects = (victim: string) =>
  passengers
    .filter((p) => p.id !== victim)
    .map((p) => ({ id: p.id, label: listedAs(p) }));

/**
 * The weapons the run can name, which are the ones it can also put in a room: the
 * model is the qualification, not the kind. TheNight draws from this same rule.
 *
 * A weapon with no model is real content -- somebody owns it, it has a page -- but
 * nothing can place it aboard, so listing it would put a row on the sheet that no
 * evidence can ever bear on and no run can ever be about.
 */
const weapons = () =>
  items
    .filter((i: Item) => i.kind === 'weapon' && i.model)
    .map((i) => ({ id: i.id, label: i.name }));

/**
 * Rooms in the consist, and not the platform. The platform is where people were
 * before they were passengers; nobody is killed there, and TheNight will not put
 * the scene there either.
 */
const rooms = () =>
  locations
    .filter((l) => typeof l.carriage === 'number')
    .map((l) => ({ id: l.id as LocationId, label: l.name }));

const MARK_TITLE: Record<Mark, string> = {
  clear: 'Not ruled on',
  out: 'Ruled out',
  likely: 'Suspected',
};

const MARK_GLYPH: Record<Mark, string> = { clear: '', out: '×', likely: '●' };

/**
 * Looked up rather than built from the mark name. An unmarked row wants no class
 * at all, and `styles[mark]` would have gone looking for one called `clear` --
 * which exists, and is the button that rubs the sheet out.
 */
const MARK_CLASS: Record<Mark, string> = {
  clear: '',
  out: styles.out,
  likely: styles.likely,
};

export function Notebook() {
  const marked = useMarkedCount();
  const victim = useVictim();
  const columns: Column[] = [
    { key: 'suspect', title: 'Who', rows: suspects(victim) },
    {
      key: 'weapon',
      title: 'With What',
      rows: weapons(),
      thin: 'Only one of these has turned up aboard so far.',
    },
    { key: 'room', title: 'Where', rows: rooms() },
  ];

  return (
    <section className={styles.block}>
      <div className={styles.scrubRow}>
        <h3 className={styles.head2}>The Notebook</h3>
        <button
          className={styles.rubOut}
          onClick={clearMarks}
          disabled={marked === 0}
          data-testid="notebook-clear"
          title={marked === 0 ? 'Nothing pencilled in yet.' : 'Rub out every mark'}
        >
          Rub out
        </button>
      </div>
      <div className={styles.notebook} data-testid="notebook">
        {columns.map((column) => (
          <div key={column.key} className={styles.column}>
            <h4 className={styles.columnHead}>{column.title}</h4>
            <ul className={styles.list}>
              {column.rows.map((row) => (
                <Row key={row.id} column={column.key} id={row.id} label={row.label} />
              ))}
            </ul>
            {column.rows.length < 2 && column.thin && (
              <p className={styles.hint}>{column.thin}</p>
            )}
          </div>
        ))}
      </div>
      <p className={styles.hint}>
        Yours to pencil in, and nobody checks it. Once for struck out, twice for
        suspected.
      </p>
    </section>
  );
}

function Row({ column, id, label }: { column: string; id: string; label: string }) {
  const key = markKey(column, id);
  const mark = useMark(key);

  return (
    <li>
      <button
        className={`${styles.pencil} ${MARK_CLASS[mark]}`}
        onClick={() => cycleMark(key)}
        data-testid={`notebook-${key}`}
        data-mark={mark}
        aria-label={`${label}: ${MARK_TITLE[mark]}`}
        title={MARK_TITLE[mark]}
      >
        <span className={styles.pencilGlyph} aria-hidden>
          {MARK_GLYPH[mark]}
        </span>
        <span className={styles.pencilName}>{label}</span>
      </button>
    </li>
  );
}
