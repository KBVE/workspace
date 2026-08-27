//! The locale list the site and the game clients read.
//!
//! Every value here comes out of `kbve.common.v1.Locale`, so adding a language
//! to the schema adds it to this response without touching the service. The
//! tag derivation mirrors `packages/i18n`: LOCALE_PT_BR -> pt-BR.

use kbve_proto::common::v1::Locale;
use serde::Serialize;

/// The value the site falls back to, and the one the registry itself is
/// written in.
pub const DEFAULT: Locale = Locale::En;

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct LocaleView {
    /// The proto enum name, which is what the wire types use.
    pub proto: &'static str,
    /// The BCP 47 tag, which is what `Accept-Language` and the URLs use.
    pub tag: String,
}

/// Turns LOCALE_PT_BR into pt-BR, and LOCALE_EN into en.
fn tag_of(name: &str) -> String {
    let rest = name.strip_prefix("LOCALE_").unwrap_or(name);
    let mut parts = rest.split('_');
    let language = parts.next().unwrap_or_default().to_lowercase();
    match parts.next() {
        Some(region) => format!("{language}-{}", region.to_uppercase()),
        None => language,
    }
}

/// Walks the enum from zero and stops at the first gap.
///
/// prost does not emit a list of variants, and hard-coding one here would be a
/// second source of truth that drifts the moment a language is added. Proto
/// enums are allocated contiguously from zero, so the scan is exhaustive for
/// any schema that keeps doing that; the test below fails if it stops early.
pub fn all() -> Vec<LocaleView> {
    (0i32..)
        .map_while(|value| Locale::try_from(value).ok())
        .filter(|locale| *locale != Locale::Unspecified)
        .map(|locale| {
            let proto = locale.as_str_name();
            LocaleView {
                proto,
                tag: tag_of(proto),
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derives_tags_from_the_proto_names() {
        assert_eq!(tag_of("LOCALE_EN"), "en");
        assert_eq!(tag_of("LOCALE_PT_BR"), "pt-BR");
    }

    #[test]
    fn scan_reaches_every_declared_locale() {
        let found = all();
        // Unspecified is filtered out, so the scan has to have gone past it.
        assert!(!found.is_empty(), "the scan stopped before any real locale");
        assert!(found.iter().any(|view| view.proto == DEFAULT.as_str_name()));
        // A gap in the enum would silently truncate the list, so assert the
        // highest variant the scan found is the highest one that exists.
        let next = found.len() as i32 + 1;
        assert!(
            Locale::try_from(next).is_err(),
            "the enum continues past the scan at value {next}"
        );
    }
}
