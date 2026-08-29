export type ExternalOpener = (url: string) => void;

let opener: ExternalOpener | null = null;

export function setExternalOpener(fn: ExternalOpener | null): void {
	opener = fn;
}

export function getExternalOpener(): ExternalOpener | null {
	return opener;
}

/**
 * These URLs arrive from server data -- a promo creative, a link typed in chat
 * -- and `noopener,noreferrer` does not cover all of them. It stops the opened
 * page reaching back through `window.opener`; it does nothing about
 * `javascript:`, which runs in the caller's own origin instead of opening a
 * page, or `data:`, which shows attacker-authored markup under the game's
 * window.
 */
const ALLOWED_PROTOCOLS = new Set(['http:', 'https:']);

/**
 * Resolved against the current document rather than string-matched, so a
 * relative path still passes -- it resolves to the page's own http(s) origin.
 */
export function isSafeExternalUrl(url: string): boolean {
	const base =
		typeof document !== 'undefined' ? document.baseURI : 'https://localhost/';
	try {
		return ALLOWED_PROTOCOLS.has(new URL(url, base).protocol);
	} catch {
		return false;
	}
}

export function openExternal(url: string): void {
	// Before the opener, not after: an embed host is handed the URL verbatim,
	// so guarding only the browser path would leave the host a way through.
	if (!isSafeExternalUrl(url)) {
		console.warn('[laser/embed] refused to open a non-http(s) URL', url);
		return;
	}
	if (opener) {
		opener(url);
		return;
	}
	if (typeof window !== 'undefined') {
		window.open(url, '_blank', 'noopener,noreferrer');
	}
}

export function onExternalClick(url: string) {
	return (e: { preventDefault: () => void }) => {
		// Cancelled with or without an opener: letting the anchor follow an
		// unsafe URL is the thing being prevented.
		if (!isSafeExternalUrl(url)) {
			e.preventDefault();
			console.warn('[laser/embed] refused to follow a non-http(s) URL', url);
			return;
		}
		if (opener) {
			e.preventDefault();
			opener(url);
		}
	};
}
