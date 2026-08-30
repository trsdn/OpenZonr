import Foundation

/// Was OpenZonr mit einer Regel *tun würde*, ohne ein Fenster zu bewegen.
///
/// Die zwei Fälle, die im Nachtrag zu Issue #19 sauber getrennt sind:
///
/// - **Fall A — ein Fenster liegt vor.** Der Snapshot wird durch dieselbe
///   Filter- und Regel-Engine geschickt, die die Platzierung selbst benutzt.
///   Wenn eine Regel gewinnt, wird ihr Zielrahmen über den Zonen-Resolver
///   ausgerechnet. Die Auskunft ist eine Messung: dieses Fenster ginge nach
///   *dort*, wegen *dieser* Regel.
///
/// - **Fall B — die App läuft nicht.** Kein Snapshot, kein Titel, keine
///   Rolle, keine Größe. Für jede aktive Regel wird beantwortet, welche
///   Kriterien überhaupt geprüft werden können und welche nicht. Kann
///   allein aus der Bundle-Kennung ein Gewinner benannt werden, ist die
///   Auskunft bedingt (**ungeprüfte** Kriterien werden namentlich mitgemeldet).
///
/// Absichtlich reine Rechnung, in Core: die einzige Bedingung an einen Test
/// ist eine Konfiguration, ein Bündel Regeln und, in Fall A, ein
/// `WindowSnapshot`. Kein `NSScreen`, kein AppKit, kein Fenstersystem.
public enum DryRunPreview {

    /// Ergebnis der Vorschau.
    public enum Result: Hashable, Sendable {
        /// Es gibt eine passende Regel; die Auskunft ist eine Messung
        /// oder eine ausgewiesene Teilauskunft.
        case matches(Match)
        /// Keine Regel greift.
        ///
        /// Für Fall A ist die Auffangregel des aktiven Profils die Antwort;
        /// sie wird als Match mit `usedFallback == true` gemeldet, nicht als
        /// `noMatch`. `noMatch` bleibt für Fall B, in dem gar kein Bundle
        /// bekannt ist oder keine Regel dieses Bundle kennt.
        case noMatch
        /// Der Zonen-Resolver konnte die Regel zwar auswählen, aber das
        /// Zieldisplay nicht auf einen Bildschirm abbilden — z. B. weil das
        /// Setup des Nutzers nicht das Setup ist, für das ein Profil gilt.
        case unresolvable(Match, ZoneResolutionFailure)
    }

    /// Die Regel, die greift, samt allem, was ohne Fenster nicht sicher ist.
    public struct Match: Hashable, Sendable {
        /// Die Regel, die gewinnt.
        public var rule: PlacementRule
        /// Die Rolle, in die sie führt (aus der Regel entnommen).
        public var role: RoleID
        /// Aufgelöste Platzierung, wenn ein aktives Profil und Snapshots
        /// bekannt sind. `nil`, wenn Fall B ohne Bildschirmauswahl gefragt
        /// wurde oder das Profil zu keinem Setup passt.
        public var placement: ResolvedPlacement?
        /// Die Auskunft über die Regel-Kriterien.
        ///
        /// Ist `undecidable` leer, ist die Antwort eine Messung. Steht hier
        /// etwas drin, muss die Oberfläche das *sichtbar* melden.
        public var report: RuleCriteria.Report
        /// Fall B: bedingte Antwort ohne Fenster. Fall A: exakte Messung.
        public var isConditional: Bool

        public init(
            rule: PlacementRule,
            role: RoleID,
            placement: ResolvedPlacement?,
            report: RuleCriteria.Report,
            isConditional: Bool
        ) {
            self.rule = rule
            self.role = role
            self.placement = placement
            self.report = report
            self.isConditional = isConditional
        }
    }

    // MARK: - Fall A: mit Fenster

    /// Fall A. Ein tatsächliches Fenster wird durch die Engine geschickt.
    ///
    /// Nutzt dieselben Bausteine wie die Platzierung selbst — `DefaultWindowFilter`,
    /// `CompiledRuleSet`, `DefaultRuleEngine`, `DefaultZoneResolver` — damit
    /// die Vorschau nicht zufällig anders rechnet als die Wirklichkeit.
    ///
    /// - Parameters:
    ///   - window: Der beobachtete Snapshot, wie `openzonr windows` ihn
    ///     erzeugt.
    ///   - configuration: Die aktuelle Konfiguration.
    ///   - snapshots: Die tatsächlich angeschlossenen Bildschirme. Bestimmen
    ///     das aktive Profil und die konkreten Zielrahmen.
    public static func evaluate(
        window: WindowSnapshot,
        configuration: Configuration,
        snapshots: [DisplaySnapshot]
    ) -> Result {
        let filter = DefaultWindowFilter()
        // Der globale Filter kommt zuerst, wie im echten Pfad. Wird das Fenster
        // abgelehnt, greift *keine* Regel — genau die Auskunft, die der Editor
        // dann geben muss.
        switch filter.evaluate(window, defaults: configuration.defaults) {
        case .accepted:
            break
        case .rejected:
            return .noMatch
        }

        let compiled = CompiledRuleSet(rules: configuration.rules)
        let engine = DefaultRuleEngine()

        if let rule = engine.firstMatch(for: window, in: compiled, defaults: configuration.defaults) {
            let report = RuleCriteria.report(for: rule.match, defaults: configuration.defaults)
            let placement = resolvePlacement(
                role: rule.action.role,
                share: rule.action.share,
                configuration: configuration,
                snapshots: snapshots
            )
            switch placement {
            case let .success(resolved):
                return .matches(Match(
                    rule: rule,
                    role: rule.action.role,
                    placement: resolved,
                    report: report,
                    isConditional: false
                ))
            case let .failure(failure):
                return .unresolvable(
                    Match(
                        rule: rule,
                        role: rule.action.role,
                        placement: nil,
                        report: report,
                        isConditional: false
                    ),
                    failure
                )
            }
        }

        return .noMatch
    }

    // MARK: - Fall B: nur Bundle-Kennung

    /// Fall B. Die App läuft nicht, es gibt keinen Snapshot.
    ///
    /// Die Regeln werden in Auswertungsreihenfolge geprüft. Eine Regel gilt
    /// hier als „möglich", wenn ihre Bundle-Kennung stimmt (oder sie gar keine
    /// hat) und keine ihrer *entscheidbaren* Kriterien den Fall ausschließt.
    /// Die *unentscheidbaren* Kriterien werden mitgemeldet — die Oberfläche
    /// muss sie zeigen, sonst hat sie das Problem gelöst, das der Nachtrag
    /// benennt: eine Vermutung im Gewand einer Rechnung.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: Die Bundle-Kennung der nicht laufenden App.
    ///   - configuration: Die aktuelle Konfiguration.
    ///   - snapshots: Optional. Werden Bildschirme mitgegeben, wird — soweit
    ///     das aktive Profil bekannt ist — auch der Zielrahmen ausgerechnet.
    ///     Werden keine mitgegeben, fehlt der Rahmen und die Zeile beschränkt
    ///     sich auf Regel, Rolle und Zone.
    public static func evaluate(
        bundleIdentifier: String,
        configuration: Configuration,
        snapshots: [DisplaySnapshot] = []
    ) -> Result {
        let compiled = CompiledRuleSet(rules: configuration.rules)

        for entry in compiled.entries {
            let match = entry.rule.match
            // Die entscheidbare Kriterien-Prüfung: nur Bundle. Alles andere
            // steht als „ungeprüft" in der Zeile.
            if let ruleBundle = match.bundleIdentifier, ruleBundle != bundleIdentifier {
                continue
            }

            let report = RuleCriteria.report(for: match, defaults: configuration.defaults)
            let placement = resolvePlacement(
                role: entry.rule.action.role,
                share: entry.rule.action.share,
                configuration: configuration,
                snapshots: snapshots
            )

            let resolvedPlacement: ResolvedPlacement?
            switch placement {
            case let .success(resolved): resolvedPlacement = resolved
            case .failure: resolvedPlacement = nil
            }

            return .matches(Match(
                rule: entry.rule,
                role: entry.rule.action.role,
                placement: resolvedPlacement,
                report: report,
                isConditional: report.requiresObservation
            ))
        }

        return .noMatch
    }

    // MARK: - Zonenauflösung

    /// Löst die Rolle über das aktive Profil und die vorhandenen Snapshots
    /// zu einem konkreten Rahmen auf.
    ///
    /// Findet sich kein aktives Profil oder passt keins der beschriebenen
    /// Displays auf einen angeschlossenen Bildschirm, kommt eine Failure
    /// zurück; die Vorschau meldet das über ``Result/unresolvable(_:_:)``.
    private static func resolvePlacement(
        role: RoleID,
        share: ZoneShare?,
        configuration: Configuration,
        snapshots: [DisplaySnapshot]
    ) -> Swift.Result<ResolvedPlacement, ZoneResolutionFailure> {
        guard !snapshots.isEmpty else {
            return .failure(.missingVisibleFrame(DisplayAlias(rawValue: "")))
        }
        let fingerprint = SetupFingerprint(snapshots: snapshots, ignoring: configuration.ignoredDisplays)
        let profileResolver = DefaultProfileResolver()
        guard let profile = profileResolver.activeProfile(for: fingerprint, in: configuration) else {
            return .failure(.missingVisibleFrame(DisplayAlias(rawValue: "")))
        }
        let arrangement = ScreenArrangement(snapshots: snapshots)
        let visibleFrames = arrangement.visibleFrames(for: configuration.displays)
        let zoneResolver = DefaultZoneResolver()
        return zoneResolver.resolve(
            role: role,
            share: share,
            profile: profile,
            configuration: configuration,
            visibleFrames: visibleFrames
        )
    }
}
