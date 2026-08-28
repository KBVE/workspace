import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, cleanup, screen, fireEvent } from '@testing-library/react';
import { AdCard } from './PromoCard';
import type { AdCreative } from './types';

const creative = (over: Partial<AdCreative> = {}): AdCreative => ({
	id: 'ad-1',
	title: 'Play Fish and Chip',
	url: 'https://kbve.com/fishchip',
	...over,
});

describe('AdCard', () => {
	afterEach(cleanup);

	it('renders the title and links to the creative', () => {
		render(<AdCard creative={creative()} />);
		const link = screen.getByRole('link');

		expect(link).toHaveProperty('href', 'https://kbve.com/fishchip');
		expect(link.textContent).toContain('Play Fish and Chip');
	});

	it('opens in a new tab with the opener severed', () => {
		render(<AdCard creative={creative()} />);
		const link = screen.getByRole('link');

		expect(link.getAttribute('target')).toBe('_blank');
		expect(link.getAttribute('rel')).toBe('noopener noreferrer');
	});

	describe('optional content', () => {
		it('omits the eyebrow, body and highlight when absent', () => {
			render(<AdCard creative={creative()} />);
			expect(screen.getByRole('link').textContent).toBe(
				'★Play Fish and Chip',
			);
		});

		it('renders each one when present', () => {
			render(
				<AdCard
					creative={creative({
						eyebrow: 'While you wait',
						highlight: 'free',
						body: 'A cozy fishing game',
					})}
				/>,
			);
			const text = screen.getByRole('link').textContent!;
			expect(text).toContain('While you wait');
			expect(text).toContain('free');
			expect(text).toContain('A cozy fishing game');
		});
	});

	describe('badge', () => {
		it('falls back to a star when there is no icon or image', () => {
			render(<AdCard creative={creative()} />);
			expect(screen.getByRole('link').textContent).toContain('★');
			expect(screen.getByRole('link').querySelector('img')).toBeNull();
		});

		it('prefers the image over the icon', () => {
			const { container } = render(
				<AdCard
					creative={creative({ icon: '🐟', imageUrl: 'https://k.b/a.png' })}
				/>,
			);
			expect(container.querySelector('img')).toHaveProperty(
				'src',
				'https://k.b/a.png',
			);
			expect(container.textContent).not.toContain('🐟');
		});

		// A creative pointing at an image that 404s would otherwise leave a
		// broken-image glyph on the boot screen.
		it('hides an image that fails to load', () => {
			const { container } = render(
				<AdCard creative={creative({ imageUrl: 'https://k.b/gone.png' })} />,
			);
			const img = container.querySelector('img')!;

			fireEvent.error(img);
			expect(img.style.display).toBe('none');
		});
	});

	describe('onOpen', () => {
		it('takes over the click when the host supplies one', () => {
			const onOpen = vi.fn();
			const ad = creative();
			render(<AdCard creative={ad} onOpen={onOpen} />);

			const event = new MouseEvent('click', { bubbles: true, cancelable: true });
			fireEvent(screen.getByRole('link'), event);

			expect(onOpen).toHaveBeenCalledWith(ad);
			expect(event.defaultPrevented).toBe(true);
		});

		it('lets the anchor navigate when the host supplies none', () => {
			render(<AdCard creative={creative()} />);

			const event = new MouseEvent('click', { bubbles: true, cancelable: true });
			fireEvent(screen.getByRole('link'), event);

			expect(event.defaultPrevented).toBe(false);
		});
	});

	// A creative is host-supplied data, so its url is no more trustworthy than
	// anything else off the wire, and rel="noopener noreferrer" is no defence
	// against a scheme that never opens a page.
	describe('an unsafe url', () => {
		// Dropping the href also drops the link role, which is the correct
		// semantics: an anchor that goes nowhere is not a link, and a screen
		// reader should not announce it as one.
		it.each(['javascript:alert(1)', 'data:text/html,<script>alert(1)</script>'])(
			'renders %s with no href and no link role',
			(url) => {
				const { container } = render(<AdCard creative={creative({ url })} />);
				expect(container.querySelector('a')!.getAttribute('href')).toBeNull();
				expect(screen.queryByRole('link')).toBeNull();
			},
		);

		it('cancels the navigation and never calls onOpen', () => {
			const onOpen = vi.fn();
			const { container } = render(
				<AdCard
					creative={creative({ url: 'javascript:alert(1)' })}
					onOpen={onOpen}
				/>,
			);

			const event = new MouseEvent('click', { bubbles: true, cancelable: true });
			fireEvent(container.querySelector('a')!, event);

			expect(event.defaultPrevented).toBe(true);
			expect(onOpen).not.toHaveBeenCalled();
		});

		it('still renders the card rather than leaving a hole', () => {
			const { container } = render(
				<AdCard creative={creative({ url: 'javascript:alert(1)' })} />,
			);
			expect(container.textContent).toContain('Play Fish and Chip');
		});
	});

	describe('styling', () => {
		it('passes through className and merges style over the defaults', () => {
			render(
				<AdCard
					creative={creative()}
					className="boot-ad"
					style={{ maxWidth: '500px' }}
				/>,
			);
			const link = screen.getByRole('link');

			expect(link.className).toBe('boot-ad');
			expect(link.style.maxWidth).toBe('500px');
		});

		it('uses the creative accent for the highlight, and gold for the default', () => {
			const { container } = render(
				<AdCard creative={creative({ highlight: 'free' })} />,
			);
			const gold = [...container.querySelectorAll('span')].some(
				(s) => s.style.color === 'rgb(252, 211, 77)',
			);
			expect(gold).toBe(true);

			cleanup();
			const custom = render(
				<AdCard creative={creative({ highlight: 'free', accent: '#ff0000' })} />,
			);
			const accented = [...custom.container.querySelectorAll('span')].some(
				(s) => s.style.color === 'rgb(255, 0, 0)',
			);
			expect(accented).toBe(true);
		});
	});
});
