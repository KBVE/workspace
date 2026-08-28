import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
	getExternalOpener,
	onExternalClick,
	openExternal,
	setExternalOpener,
} from './external';

describe('external links', () => {
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

	describe('openExternal', () => {
		it('opens in a new tab with the opener severed', () => {
			openExternal('https://kbve.com');
			expect(open).toHaveBeenCalledWith(
				'https://kbve.com',
				'_blank',
				'noopener,noreferrer',
			);
		});

		it('prefers an installed opener over the browser', () => {
			const opener = vi.fn();
			setExternalOpener(opener);
			openExternal('https://kbve.com');

			expect(opener).toHaveBeenCalledWith('https://kbve.com');
			expect(open).not.toHaveBeenCalled();
		});

		// These URLs reach this function from server data -- a promo creative, a
		// link in chat. `noopener,noreferrer` defends against the opened page
		// reaching back; it does nothing about a scheme that never opens a page
		// at all and instead runs in the caller's own context.
		it.each([
			'javascript:alert(document.cookie)',
			'JavaScript:alert(1)',
			'  javascript:alert(1)',
			'data:text/html,<script>alert(1)</script>',
			'vbscript:msgbox(1)',
			'file:///etc/passwd',
		])('refuses to open %s', (url) => {
			openExternal(url);
			expect(open).not.toHaveBeenCalled();
		});

		it('refuses a dangerous scheme even through an installed opener', () => {
			const opener = vi.fn();
			setExternalOpener(opener);
			openExternal('javascript:alert(1)');
			expect(opener).not.toHaveBeenCalled();
		});

		it('still allows a relative path, which resolves to the page origin', () => {
			openExternal('/about');
			expect(open).toHaveBeenCalledWith(
				'/about',
				'_blank',
				'noopener,noreferrer',
			);
		});

		it('refuses a URL that cannot be parsed at all', () => {
			openExternal('http://[');
			expect(open).not.toHaveBeenCalled();
		});
	});

	describe('setExternalOpener', () => {
		it('reads back what was installed, and clears with null', () => {
			const opener = vi.fn();
			setExternalOpener(opener);
			expect(getExternalOpener()).toBe(opener);
			setExternalOpener(null);
			expect(getExternalOpener()).toBeNull();
		});
	});

	describe('onExternalClick', () => {
		it('takes over the click when an opener is installed', () => {
			const opener = vi.fn();
			setExternalOpener(opener);
			const preventDefault = vi.fn();

			onExternalClick('https://kbve.com')({ preventDefault });

			expect(preventDefault).toHaveBeenCalled();
			expect(opener).toHaveBeenCalledWith('https://kbve.com');
		});

		// With no opener the anchor's own navigation is the correct behaviour,
		// so the handler must leave the event alone.
		it('lets the browser follow the link when there is no opener', () => {
			const preventDefault = vi.fn();
			onExternalClick('https://kbve.com')({ preventDefault });
			expect(preventDefault).not.toHaveBeenCalled();
		});

		it('blocks the navigation for a dangerous scheme', () => {
			const opener = vi.fn();
			setExternalOpener(opener);
			const preventDefault = vi.fn();

			onExternalClick('javascript:alert(1)')({ preventDefault });

			expect(preventDefault).toHaveBeenCalled();
			expect(opener).not.toHaveBeenCalled();
		});
	});
});
