import AppKit

/// Get Long Weekend companion (`get-long-weekend`, trailing, 2 pins).
///
/// State A (Discovery): static local card, zero network calls, opens
/// https://getlongweekend.ca. State B (Personal Countdown): countdown to
/// the next upcoming block of the idempotently synced plan, with per-block
/// T-7d reminder slips pinned by `HolidayPlanStore`.
@MainActor
public final class GetLongWeekendPiece: NSObject, CompanionPiece {
    public let pieceID = "get-long-weekend"
    public let displayName = "Get Long Weekend"
    public nonisolated var id: String { pieceID }
    public let sizeMetrics = PieceSizeMetrics(width: 170, height: 205, massUnits: 6.0)
    public let pinCount = 2
    public let preferredSide = PieceAnchorSide.trailing

    /// This piece never drives weather physics.
    public var environmentalBroadcast: EnvironmentSnapshot? { nil }

    private let container = NSView()
    private let stack = NSStackView()
    private let headline = NSTextField(labelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    private let planStore: HolidayPlanStore

    @MainActor public var pieceView: NSView { container }

    public init(planStore: HolidayPlanStore) {
        self.planStore = planStore
        super.init()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 10
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        headline.font = .boldSystemFont(ofSize: 13)
        headline.lineBreakMode = .byWordWrapping
        countdownLabel.font = .systemFont(ofSize: 12)
        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(openSite)
        stack.addArrangedSubview(headline)
        stack.addArrangedSubview(countdownLabel)
        stack.addArrangedSubview(actionButton)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
        ])
        render()
    }

    public func render() {
        let locale = AppLocale.current()
        let today = HolidayPlanStore.todayString()
        if let (_, block) = planStore.nextUpcomingBlock(today: today) {
            // State B: Personal Countdown.
            headline.stringValue = locale == .pt ? "Feriad\u{00E3}o" : "Long weekend"
            if block.startDate < today {
                countdownLabel.stringValue = UIStrings.underwayCountdown(endDate: block.endDate, locale: locale)
            } else {
                let days = HolidayPlanStore.daysUntil(start: block.startDate, from: today) ?? 0
                let dayWord = locale == .pt ? (days == 1 ? "dia" : "dias") : (days == 1 ? "day" : "days")
                countdownLabel.stringValue = locale == .pt
                    ? "em \(days) \(dayWord) \u{00B7} \(block.startDate) \u{2013} \(block.endDate)"
                    : "in \(days) \(dayWord) \u{00B7} \(block.startDate) \u{2013} \(block.endDate)"
            }
            actionButton.title = locale == .pt ? "Ver plano \u{2197}" : "View plan \u{2197}"
        } else {
            // State A: Discovery (static, zero network calls).
            headline.stringValue = UIStrings.discoveryHeadline(locale: locale)
            countdownLabel.stringValue = locale == .pt ? "Planeje no site" : "Plan on the site"
            actionButton.title = locale == .pt ? "Planejar datas \u{2197}" : "Plan dates \u{2197}"
        }
    }

    @objc private func openSite() {
        if let url = URL(string: "https://getlongweekend.ca") {
            NSWorkspace.shared.open(url)
        }
    }
}
