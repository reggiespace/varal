import Foundation

/// Bilingual UI strings (EN/PT). Source of truth is docs/designs/varal.md;
/// the reminder-slip templates use the doc's exact characters.
public enum AppLocale: String, Sendable {
    case en = "en"
    case pt = "pt"

    public static func current() -> AppLocale {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code.hasPrefix("pt") ? .pt : .en
    }
}

public enum UIStrings {
    // MARK: - Get Long Weekend reminder slip (exact doc templates)

    /// EN: `Long weekend (<start> – <end>) — confirm time off`
    /// (U+2013 EN DASH inside parens, U+2014 EM DASH before the verb).
    public static func reminderTitleEN(start: String, end: String) -> String {
        "Long weekend (\(start) \u{2013} \(end)) \u{2014} confirm time off"
    }

    /// PT: `Feriadão (<start> – <end>) — confirmar folga`.
    public static func reminderTitlePT(start: String, end: String) -> String {
        "Feriad\u{00E3}o (\(start) \u{2013} \(end)) \u{2014} confirmar folga"
    }

    public static func reminderTitle(start: String, end: String, locale: AppLocale) -> String {
        switch locale {
        case .en: return reminderTitleEN(start: start, end: end)
        case .pt: return reminderTitlePT(start: start, end: end)
        }
    }

    public static let reminderTimeLabel = "T-7d"

    // MARK: - Discovery card (State A)

    public static func discoveryHeadline(locale: AppLocale) -> String {
        switch locale {
        case .en: return "Turn 1 PTO day into 4 days off"
        case .pt: return "Transforme 1 dia de folga em 4"
        }
    }

    // MARK: - Basket

    public static func dayCompleteCaption(doneCount: Int, locale: AppLocale) -> String {
        switch locale {
        case .en: return "Day complete \u{00B7} \(doneCount) done"
        case .pt: return "Dia conclu\u{00ED}do \u{00B7} \(doneCount) feitas"
        }
    }

    public static func emptyBasket(locale: AppLocale) -> String {
        switch locale {
        case .en: return "Empty basket"
        case .pt: return "Limpar cesto"
        }
    }
}
