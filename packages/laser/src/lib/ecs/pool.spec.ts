import { describe, it, expect, beforeEach } from 'vitest';
import {
	addComponent,
	addEntity,
	createWorld,
	removeComponent,
	type World,
} from './bitecs';
import { Prop } from './props';
import { EntityPool } from './pool';

/** Records what the pool created and destroyed, which is the whole contract. */
class TestPool extends EntityPool<{ eid: number; alive: boolean }> {
	created: number[] = [];
	destroyed: number[] = [];

	protected create(eid: number) {
		this.created.push(eid);
		return { eid, alive: true };
	}

	protected destroy(item: { eid: number; alive: boolean }) {
		item.alive = false;
		this.destroyed.push(item.eid);
	}
}

describe('EntityPool', () => {
	let world: World;
	let pool: TestPool;

	beforeEach(() => {
		world = createWorld();
		pool = new TestPool([Prop]);
	});

	const spawn = () => {
		const eid = addEntity(world);
		addComponent(world, eid, Prop);
		return eid;
	};

	it('creates one item per newly matching entity', () => {
		const a = spawn();
		const b = spawn();
		pool.reconcile(world);

		expect(pool.created).toEqual([a, b]);
		expect(pool.size).toBe(2);
	});

	it('creates nothing on a reconcile that changes nothing', () => {
		spawn();
		pool.reconcile(world);
		pool.reconcile(world);

		expect(pool.created).toHaveLength(1);
		expect(pool.destroyed).toHaveLength(0);
	});

	it('destroys the item of an entity that stopped matching', () => {
		const a = spawn();
		const b = spawn();
		pool.reconcile(world);

		removeComponent(world, a, Prop);
		pool.reconcile(world);

		expect(pool.destroyed).toEqual([a]);
		expect(pool.size).toBe(1);
		expect([...pool.entries()].map(([eid]) => eid)).toEqual([b]);
	});

	it('destroys everything it holds on dispose and forgets it', () => {
		spawn();
		spawn();
		pool.reconcile(world);
		pool.dispose();

		expect(pool.destroyed).toHaveLength(2);
		expect(pool.size).toBe(0);
	});

	// dispose() empties the map rather than marking the pool dead, so a pool
	// reconciled again rebuilds instead of resurrecting stale render objects.
	it('rebuilds after dispose rather than reusing destroyed items', () => {
		const a = spawn();
		pool.reconcile(world);
		pool.dispose();
		pool.reconcile(world);

		expect(pool.created).toEqual([a, a]);
		expect([...pool.entries()][0][1].alive).toBe(true);
	});
});
