import { describe, it, expect, beforeEach } from 'vitest';
import {
	addComponent,
	addEntity,
	createWorld,
	entityExists,
	query,
	type World,
} from './bitecs';
import { Prop, Stone, despawnWhere } from './props';

describe('despawnWhere', () => {
	let world: World;

	beforeEach(() => {
		world = createWorld();
	});

	/** A prop belonging to container `owner`. */
	const prop = (owner: number): number => {
		const eid = addEntity(world);
		addComponent(world, eid, Prop);
		Prop.ownerEid[eid] = owner;
		return eid;
	};

	it('removes only the entities whose field matches', () => {
		const mine = [prop(7), prop(7)];
		const theirs = prop(9);

		expect(despawnWhere(world, Prop, 'ownerEid', 7)).toBe(2);
		for (const eid of mine) expect(entityExists(world, eid)).toBe(false);
		expect(entityExists(world, theirs)).toBe(true);
	});

	it('removes nothing when no entity matches', () => {
		prop(7);
		expect(despawnWhere(world, Prop, 'ownerEid', 999)).toBe(0);
		expect(query(world, [Prop])).toHaveLength(1);
	});

	// The query result is a live view, so removing while iterating it drops
	// entities the loop has not reached yet. Collecting first is what makes a
	// full sweep actually remove everything it matched.
	it('removes every match when the whole set matches', () => {
		for (let i = 0; i < 8; i++) prop(3);
		expect(despawnWhere(world, Prop, 'ownerEid', 3)).toBe(8);
		expect(query(world, [Prop])).toHaveLength(0);
	});

	it('works on any component and field, not just Prop.ownerEid', () => {
		const a = addEntity(world);
		addComponent(world, a, Stone);
		Stone.ore[a] = 2;
		const b = addEntity(world);
		addComponent(world, b, Stone);
		Stone.ore[b] = 5;

		expect(despawnWhere(world, Stone, 'ore', 2)).toBe(1);
		expect(entityExists(world, a)).toBe(false);
		expect(entityExists(world, b)).toBe(true);
	});
});
