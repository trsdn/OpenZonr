import Testing
@testable import OpenZonrCore

/// The sentence shown in the menu once a drag is over.
///
/// It is the only feedback about a drag a user ever sees — and the only clue
/// left by the open bug "zones don't come with ⌘". A wrong sentence sends the
/// search in the wrong direction, so every wording is pinned down here
/// individually.
///
/// The expected text is the English `value` each `L.string(...)` call
/// carries in `DragOutcome.swift` — there is no German catalog entry for
/// these keys yet, so the English fallback is exactly what runs today,
/// regardless of locale. Once a German translation is added, this file needs
/// no change: it tests the (source-language) wording `L.string` produces
/// when nothing overrides it, not a specific locale.
@Suite("Last drag — the sentence in the menu")
struct DragOutcomeWordingTests {

    @Test("No observed drag means no line")
    func noOutcomeNoLine() {
        #expect(DragOutcomeWording.sentence(for: nil) == nil)
    }

    @Test("Zones seen")
    func shown() {
        #expect(DragOutcomeWording.sentence(for: .zonesShown) == "Last drag: zones were shown.")
    }

    @Test("The case from the open bug: ⌘ was not held down")
    func awaitingCommand() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.awaitingModifier(.command)))
                == "Last drag: no zones — ⌘ was not held down."
        )
    }

    @Test("The old polarity: the key suppressed the zones")
    func suppressed() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.suppressed(.option)))
                == "Last drag: no zones — ⌥ was held down."
        )
    }

    @Test("Disabled names the menu entry, not the field in the file")
    func disabled() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.disabled))
                == "Last drag: no zones — “Zones while dragging” is set to “Off”."
        )
    }

    @Test("Too short a drag — no numbers")
    func belowThreshold() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.belowThreshold(travelled: 3, required: 12)))
                == "Last drag: no zones — the drag was too short."
        )
    }

    @Test("A key with no symbol leaves no gap in the sentence")
    func noneModifier() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.awaitingModifier(.none)))
                == "Last drag: no zones."
        )
    }

    @Test("No setup active")
    func noSetup() {
        #expect(
            DragOutcomeWording.sentence(for: .noSetupActive)
                == "Last drag: no zones — no setup is active for the connected screens."
        )
    }

    @Test("No window under the pointer")
    func noWindow() {
        #expect(
            DragOutcomeWording.sentence(for: .noWindowFound)
                == "Last drag: no window detected under the pointer."
        )
    }

    @Test("No movement evidence — the two reasons sound different")
    func noEvidence() {
        #expect(
            DragOutcomeWording.sentence(for: .noMovementEvidence(.budgetExhausted))
                == "Last drag: movement not recognized as a window drag."
        )
        #expect(
            DragOutcomeWording.sentence(for: .noMovementEvidence(.resizedInstead))
                == "Last drag: the window was resized, not moved."
        )
    }

    @Test("Released before the evidence arrived")
    func released() {
        #expect(
            DragOutcomeWording.sentence(for: .releasedBeforeEvidence)
                == "Last drag: released before the window moved."
        )
    }

    /// The reason text itself is a plain test fixture, not real
    /// `EventTapDragTracker` output — that source is still German and not
    /// migrated yet (see the comment on `.cancelled` in `DragOutcome.swift`),
    /// so a real cancellation sentence can currently read as English glued to
    /// a German clause. This test only pins down that the reason is embedded
    /// verbatim, in English, since its own fixture is English.
    @Test("A cancellation names its reason")
    func cancelled() {
        #expect(
            DragOutcomeWording.sentence(for: .cancelled(reason: "The tap was disabled."))
                == "Last drag: cancelled — The tap was disabled."
        )
    }

    @Test("A `show` arriving wrapped as `hidden` does not lie")
    func hiddenShowIsStillShown() {
        #expect(DragOutcomeWording.sentence(for: .zonesHidden(.show)) == "Last drag: zones were shown.")
    }

    @Test("Every key symbol stands for exactly one key")
    func symbols() {
        #expect(DropzoneModifier.command.symbol == "⌘")
        #expect(DropzoneModifier.option.symbol == "⌥")
        #expect(DropzoneModifier.control.symbol == "⌃")
        #expect(DropzoneModifier.shift.symbol == "⇧")
        #expect(DropzoneModifier.none.symbol == nil)
    }
}
