import { Locale as ProtoLocale } from '@kbve/protobuf/kbve/common/v1/locale.ts';

/**
 * Web adapter over the ecosystem's locale registry.
 *
 * The registry itself is `kbve.common.v1.Locale` in the protobuf schemas, so
 * the website, the game clients and the API all read the same list. This
 * module adds only what a website needs on top of it — URL prefixes, endonyms
 * — which is why those live here and not in the schema: a Unity build has no
 * use for a URL rule.
 *
 * Adding a language is one enum value in locale.proto. Everything below
 * derives from it.
 */

/** `LOCALE_PT_BR` -> `pt-BR`. */
function toTag(name: string): string {
  const [language, ...region] = name.replace(/^LOCALE_/, '').toLowerCase().split('_');
  return region.length ? `${language}-${region.join('-').toUpperCase()}` : language;
}

const registered = Object.values(ProtoLocale).filter(
  (value): value is string =>
    typeof value === 'string' && value.startsWith('LOCALE_') && value !== 'LOCALE_UNSPECIFIED',
);

export const locales = registered.map(toTag) as readonly string[] as readonly [string, ...string[]];

export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = 'en';

/**
 * URL and directory form of a locale: always lower case.
 *
 * BCP 47 capitalises the region (`pt-BR`), but URLs are conventionally lower
 * case and Astro's glob loader lowercases content ids, so the two forms have
 * to be distinguished rather than assumed equal.
 */
export function localeSlug(locale: Locale): string {
  return locale.toLowerCase();
}

/** Canonical locale for a URL or directory segment, case-insensitively. */
export function resolveLocale(segment: string): Locale | undefined {
  const wanted = segment.toLowerCase();
  return locales.find((locale) => locale.toLowerCase() === wanted);
}

/** Back to the protobuf value, for anything crossing the wire. */
export function toProto(locale: Locale): ProtoLocale {
  return `LOCALE_${locale.replace('-', '_').toUpperCase()}` as ProtoLocale;
}

export function fromProto(value: ProtoLocale): Locale {
  return toTag(value);
}

/** Endonyms: a picker should name a language the way its speakers write it. */
export const localeNames: Record<string, string> = {
  en: 'English',
};

export function isLocale(value: string): value is Locale {
  return locales.includes(value);
}

/** URL for a slug within a locale. The default locale is served unprefixed. */
export function localizePath(locale: Locale, slug: string): string {
  const path = slug.replace(/^\/+|\/+$/g, '');
  const prefix = locale === defaultLocale ? '' : `/${localeSlug(locale)}`;
  return path ? `${prefix}/${path}` : prefix || '/';
}

/** Inverse of `localizePath`: recover the shared slug from a pathname. */
export function stripLocale(pathname: string): string {
  const prefixed = locales.filter((l) => l !== defaultLocale).map(localeSlug);
  const pattern = prefixed.length ? new RegExp(`^/(${prefixed.join('|')})(?=/|$)`, 'i') : null;
  const bare = pattern ? pathname.replace(pattern, '') : pathname;
  return bare.replace(/^\/+|\/+$/g, '');
}
