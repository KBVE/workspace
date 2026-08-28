export type ExternalOpener = (url: string) => void;

let opener: ExternalOpener | null = null;

export function setExternalOpener(fn: ExternalOpener | null): void {
	opener = fn;
}

export function getExternalOpener(): ExternalOpener | null {
	return opener;
}

/**
 * Schemes a link is allowed to use. Everything else is refused.
 *
 * These URLs arrive from server data -- a promo creative, a link someone typed
 * in chat -- and `noopener,noreferrer` is not a defence against all of them. It
 * stops the opened page reaching back through `window.opener`; it does nothing
 * about `javascript:`, which opens no page at all and instead runs in the
 * caller's own origin, or about `data:`, which loads attacker-authored markup
 * that a user then sees under the game's own window.
 */
const ALLOWED_PROTOCOLS = new Set(['http:', 'https:']);

/**
 * Whether `url` is safe to hand to a browser or an embed host.
 *
 * Resolved against the current document, so an ordinary relative path stays
 * usable: it resolves to the page's own http(s) origin and passes. Anything
 * that cannot be parsed at all is refused rather than guessed at.
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
	// Checked before the opener, not after. An embed host is handed the URL
	// verbatim -- Discord's openExternalLink, for one -- so validating only the
	// browser path would leave the host as an unguarded way through.
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
		// An unsafe URL has its navigation cancelled whether or not an opener is
		// installed: letting the anchor follow it is the very thing being
		// prevented. A safe URL with no opener is left alone, because then the
		// anchor's own navigation is the correct behaviour.
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
