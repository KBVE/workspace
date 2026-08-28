import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
	encourageHardwareAcceleration,
	installDiscordExternal,
	type DiscordExternalSdk,
} from './discord-external';
import { getExternalOpener, openExternal, setExternalOpener } from './external';

const makeSdk = () => ({
	commands: {
		openExternalLink: vi.fn().mockResolvedValue(undefined),
		encourageHardwareAcceleration: vi.fn().mockResolvedValue(undefined),
	},
});

describe('discord embed', () => {
	let open: ReturnType<typeof vi.fn>;

	beforeEach(() => {
		setExternalOpener(null);
		open = vi.fn();
		vi.stubGlobal('window', { ...globalThis.window, open });
	});

	afterEach(() => {
		setExternalOpener(null);
		vi.unstubAllGlobals();
	});

	it('routes links through the SDK once installed', () => {
		const sdk = makeSdk();
		installDiscordExternal(sdk);
		openExternal('https://kbve.com');

		expect(sdk.commands.openExternalLink).toHaveBeenCalledWith({
			url: 'https://kbve.com',
		});
		expect(open).not.toHaveBeenCalled();
	});

	it('installs an opener that can be read back', () => {
		installDiscordExternal(makeSdk());
		expect(getExternalOpener()).toBeTypeOf('function');
	});

	// Inside the Discord client there is no tab to fall back to, so a failed
	// openExternalLink has nowhere to go. Left unhandled it would surface as an
	// unhandled rejection in the embed rather than as anything a player can act
	// on, which is why it is swallowed rather than rethrown.
	it('survives the SDK rejecting a link', async () => {
		const sdk = makeSdk();
		sdk.commands.openExternalLink.mockRejectedValue(new Error('denied'));
		installDiscordExternal(sdk);

		expect(() => openExternal('https://kbve.com')).not.toThrow();
		await vi.waitFor(() =>
			expect(sdk.commands.openExternalLink).toHaveBeenCalled(),
		);
	});

	// The scheme check sits in openExternal ahead of the opener, so an embed
	// host never receives a URL the browser path would have refused.
	it('never hands the SDK a non-http(s) URL', () => {
		const sdk = makeSdk();
		installDiscordExternal(sdk);
		openExternal('javascript:alert(1)');

		expect(sdk.commands.openExternalLink).not.toHaveBeenCalled();
	});

	it('asks the client for hardware acceleration, and survives a refusal', () => {
		const sdk = makeSdk();
		encourageHardwareAcceleration(sdk);
		expect(sdk.commands.encourageHardwareAcceleration).toHaveBeenCalled();

		sdk.commands.encourageHardwareAcceleration.mockRejectedValue(
			new Error('nope'),
		);
		expect(() => encourageHardwareAcceleration(sdk)).not.toThrow();
	});
});
