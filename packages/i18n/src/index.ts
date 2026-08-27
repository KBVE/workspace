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

/**
 * `LOCALE_PT_BR` -> `pt-BR`, at the type level.
 *
 * The union is computed from the generated enum rather than written out, so it
 * cannot drift from the schema, and a typo in a locale is a compile error
 * instead of a value that silently routes nowhere.
 */
type ProtoValue = (typeof ProtoLocale)[keyof typeof ProtoLocale];

/** Enum values that name an actual language. */
type LanguageValue = Exclude<ProtoValue, 'LOCALE_UNSPECIFIED' | 'UNRECOGNIZED'>;

/** `EN` -> `en`, `PT_BR` -> `pt-BR`. */
type Tagify<S extends string> = S extends `${infer Language}_${infer Region}`
  ? `${Lowercase<Language>}-${Uppercase<Region>}`
  : Lowercase<S>;

type TagOf<S extends string> = S extends `LOCALE_${infer Rest}` ? Tagify<Rest> : never;

/** `LOCALE_PT_BR` -> `pt-BR`, at runtime. Mirrors `TagOf`. */
function toTag(name: string): string {
  const [language, ...region] = name.replace(/^LOCALE_/, '').toLowerCase().split('_');
  return region.length ? `${language}-${region.join('-').toUpperCase()}` : language;
}

/** Every language the schemas declare: `'en' | 'pt-BR' | ...`. */
export type Locale = TagOf<LanguageValue>;

// UNSPECIFIED is proto's required zero value and UNRECOGNIZED is ts-proto's
// escape hatch for a value this build does not know; neither is a language.
const registered = Object.values(ProtoLocale).filter(
  (value): value is LanguageValue =>
    value !== ProtoLocale.UNSPECIFIED && value !== ProtoLocale.UNRECOGNIZED,
);

export const locales: readonly Locale[] = registered.map((value) => toTag(value) as Locale);

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

/**
 * Protobuf value to locale tag. UNSPECIFIED and UNRECOGNIZED are not
 * languages, so they resolve to nothing rather than being coerced into one.
 */
export function fromProto(value: ProtoLocale): Locale | undefined {
  if (value === ProtoLocale.UNSPECIFIED || value === ProtoLocale.UNRECOGNIZED) {
    return undefined;
  }
  return toTag(value) as Locale;
}

/** Endonyms: a picker should name a language the way its speakers write it. */
export const localeNames: Record<Locale, string> = {
  en: 'English',
};

export function isLocale(value: string): value is Locale {
  return (locales as readonly string[]).includes(value);
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
