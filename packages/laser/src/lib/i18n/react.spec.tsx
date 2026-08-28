import { describe, it, expect, afterEach } from 'vitest';
import { act, cleanup, render, screen } from '@testing-library/react';
import { I18nProvider, useTranslation } from './react';
import { I18nStore, laserI18n } from './store';

function Reader() {
	const { t, locale, setLocale } = useTranslation();
	return (
		<div>
			<span data-testid="locale">{locale}</span>
			<span data-testid="greeting">{t('hello', { name: 'Al' })}</span>
			<button onClick={() => setLocale('fr')}>fr</button>
		</div>
	);
}

const store = () =>
	new I18nStore({
		locale: 'en',
		messages: {
			en: { hello: 'Hello {name}' },
			fr: { hello: 'Bonjour {name}' },
		},
	});

describe('useTranslation', () => {
	afterEach(cleanup);

	it('translates through the store in the provider', () => {
		render(
			<I18nProvider store={store()}>
				<Reader />
			</I18nProvider>,
		);
		expect(screen.getByTestId('greeting').textContent).toBe('Hello Al');
		expect(screen.getByTestId('locale').textContent).toBe('en');
	});

	// The store is external state, so a locale change has to re-render every
	// consumer rather than only whichever one called setLocale.
	it('re-renders when the locale changes', () => {
		const s = store();
		render(
			<I18nProvider store={s}>
				<Reader />
			</I18nProvider>,
		);

		act(() => s.setLocale('fr'));

		expect(screen.getByTestId('locale').textContent).toBe('fr');
		expect(screen.getByTestId('greeting').textContent).toBe('Bonjour Al');
	});

	it('routes setLocale from a consumer back to the store', () => {
		const s = store();
		render(
			<I18nProvider store={s}>
				<Reader />
			</I18nProvider>,
		);

		act(() => screen.getByRole('button').click());

		expect(s.getLocale()).toBe('fr');
		expect(screen.getByTestId('locale').textContent).toBe('fr');
	});

	// The context defaults to the shared singleton, so a component can call
	// useTranslation without anyone having mounted a provider.
	it('falls back to the shared store with no provider', () => {
		render(<Reader />);
		expect(screen.getByTestId('locale').textContent).toBe(
			laserI18n.getLocale(),
		);
	});

	it('keeps two providers with different stores apart', () => {
		const a = store();
		const b = store();
		b.setLocale('fr');

		render(
			<>
				<I18nProvider store={a}>
					<Reader />
				</I18nProvider>
				<I18nProvider store={b}>
					<Reader />
				</I18nProvider>
			</>,
		);

		const [first, second] = screen.getAllByTestId('greeting');
		expect(first.textContent).toBe('Hello Al');
		expect(second.textContent).toBe('Bonjour Al');
	});
});
