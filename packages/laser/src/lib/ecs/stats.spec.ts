import { describe, it, expect, beforeEach } from 'vitest';
import { addEntity, createWorld, hasComponent, type World } from './bitecs';
import { Energy, Health, Mana, Stamina } from './components';
import {
	EnergyPool,
	HealthPool,
	ManaPool,
	StaminaPool,
	applyStats,
	canAfford,
	drain,
	frac,
	regenPools,
	restore,
	setPool,
} from './stats';

describe('pool operations', () => {
	// The component stores are module-level typed arrays shared by every world,
	// so each test seeds the entity it uses rather than trusting a clean slate.
	const eid = 1;

	beforeEach(() => setPool(HealthPool, eid, 50, 100, 0));

	it('reports the fraction filled, and 0 for a pool with no max', () => {
		expect(frac(HealthPool, eid)).toBe(0.5);
		setPool(HealthPool, eid, 0, 0);
		expect(frac(HealthPool, eid)).toBe(0);
	});

	it('affords exactly its current value', () => {
		expect(canAfford(HealthPool, eid, 50)).toBe(true);
		expect(canAfford(HealthPool, eid, 50.01)).toBe(false);
	});

	it('drains what it can and reports how much that was', () => {
		expect(drain(HealthPool, eid, 20)).toBe(20);
		expect(HealthPool.value[eid]).toBe(30);
	});

	it('stops draining at zero rather than going negative', () => {
		expect(drain(HealthPool, eid, 80)).toBe(50);
		expect(HealthPool.value[eid]).toBe(0);
	});

	// Without a floor, a negative amount inverts the subtraction: the pool gains
	// value, past its own max, from a call named drain.
	it('takes nothing for a negative amount', () => {
		expect(drain(HealthPool, eid, -30)).toBe(0);
		expect(HealthPool.value[eid]).toBe(50);
	});

	it('restores up to max and no further', () => {
		restore(HealthPool, eid, 30);
		expect(HealthPool.value[eid]).toBe(80);
		restore(HealthPool, eid, 999);
		expect(HealthPool.value[eid]).toBe(100);
	});

	// The mirror of the drain case: a negative restore would drain, and past
	// zero, because the clamp above it only looks at max.
	it('adds nothing for a negative amount', () => {
		restore(HealthPool, eid, -30);
		expect(HealthPool.value[eid]).toBe(50);
	});
});

describe('regenPools', () => {
	let world: World;
	let eid: number;

	beforeEach(() => {
		world = createWorld();
		eid = addEntity(world);
	});

	it('regenerates toward max at regen per second', () => {
		applyStats(world, eid, { hp: 50, maxHp: 100, hpRegen: 10 });
		regenPools(world, 0.5);
		expect(HealthPool.value[eid]).toBe(55);
	});

	it('never overshoots max', () => {
		applyStats(world, eid, { hp: 99, maxHp: 100, hpRegen: 10 });
		regenPools(world, 10);
		expect(HealthPool.value[eid]).toBe(100);
	});

	it('leaves a pool with no regen alone', () => {
		applyStats(world, eid, { hp: 50, maxHp: 100 });
		regenPools(world, 10);
		expect(HealthPool.value[eid]).toBe(50);
	});

	// A negative regen is how a damage-over-time effect is expressed through the
	// same field. It has to stop at zero, or the entity accumulates negative
	// health that every `frac` and `canAfford` downstream then reads as valid.
	it('floors a draining pool at zero', () => {
		applyStats(world, eid, { hp: 10, maxHp: 100, hpRegen: -10 });
		regenPools(world, 5);
		expect(HealthPool.value[eid]).toBe(0);
	});

	it('regenerates every pool kind, not just health', () => {
		applyStats(world, eid, {
			hp: 0,
			maxHp: 10,
			hpRegen: 1,
			mp: 0,
			maxMp: 10,
			mpRegen: 2,
			ep: 0,
			maxEp: 10,
			epRegen: 3,
			sp: 0,
			maxSp: 10,
			spRegen: 4,
		});
		regenPools(world, 1);
		expect([
			HealthPool.value[eid],
			ManaPool.value[eid],
			EnergyPool.value[eid],
			StaminaPool.value[eid],
		]).toEqual([1, 2, 3, 4]);
	});
});

describe('applyStats', () => {
	let world: World;
	let eid: number;

	beforeEach(() => {
		world = createWorld();
		eid = addEntity(world);
	});

	it('attaches only the pools the block names', () => {
		applyStats(world, eid, { maxHp: 100, maxMp: 20 });
		expect(hasComponent(world, eid, Health)).toBe(true);
		expect(hasComponent(world, eid, Mana)).toBe(true);
		expect(hasComponent(world, eid, Energy)).toBe(false);
		expect(hasComponent(world, eid, Stamina)).toBe(false);
	});

	it('spawns full when only a max is given', () => {
		applyStats(world, eid, { maxHp: 80 });
		expect(HealthPool.value[eid]).toBe(80);
		expect(HealthPool.max[eid]).toBe(80);
	});

	it('takes the current value as the max when only a value is given', () => {
		applyStats(world, eid, { hp: 40 });
		expect(HealthPool.max[eid]).toBe(40);
	});

	it('defaults regen to zero', () => {
		applyStats(world, eid, { maxHp: 80 });
		expect(HealthPool.regen[eid]).toBe(0);
	});

	it('attaches nothing for an empty block', () => {
		applyStats(world, eid, {});
		expect(hasComponent(world, eid, Health)).toBe(false);
	});
});
