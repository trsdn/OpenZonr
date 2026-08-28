import AppKit
import OpenZonrCore

/// „Diese App immer hier öffnen?“ — asked next to the window that was just
/// dropped, and easy to ignore.
///
/// An `NSAlert` was the obvious choice and is wrong here: it activates the app,
/// which takes focus away from the window the user just placed, one gesture
/// after they deliberately put it somewhere. A `.nonactivatingPanel` asks the
/// question without touching the focus; clicking it is the first moment
/// OpenZonr comes forward.
///
/// It disappears on its own after `lifetime`. An offer nobody answered is not a
/// decision to keep waiting for.
@MainActor
final class DropOfferPanel {

    private var panel: NSPanel?
    private var dismissal: Timer?
    private var onAccept: (() -> Void)?

    /// How long the offer stays up.
    ///
    /// Long enough to read a sentence and decide, short enough that it is gone
    /// before the next drag — otherwise the answer would apply to the wrong drop.
    private let lifetime: TimeInterval = 8

    func show(question: String, near point: ScreenPoint, accept: @escaping () -> Void) {
        dismiss()
        onAccept = accept

        let content = OfferView(question: question, target: self)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: content.fittingSize.height + 24),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content

        // Above the drop point, not under the pointer: the pointer is where the
        // user is looking, and a panel there would land under the cursor of the
        // very next click.
        panel.setFrameOrigin(NSPoint(x: point.x - 170, y: point.y + 24))
        panel.orderFrontRegardless()
        self.panel = panel

        dismissal = Timer.scheduledTimer(withTimeInterval: lifetime, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func dismiss() {
        dismissal?.invalidate()
        dismissal = nil
        panel?.orderOut(nil)
        panel = nil
        onAccept = nil
    }

    fileprivate func accept() {
        let action = onAccept
        dismiss()
        action?()
    }
}

/// The panel's contents: one sentence, two buttons.
private final class OfferView: NSView {

    private weak var target: DropOfferPanel?

    init(question: String, target: DropOfferPanel) {
        self.target = target
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 96))
        wantsLayer = true

        let background = NSVisualEffectView(frame: bounds)
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.autoresizingMask = [.width, .height]
        addSubview(background)

        let label = NSTextField(wrappingLabelWithString: question)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let yes = NSButton(title: "Immer hier", target: self, action: #selector(accept))
        yes.keyEquivalent = "\r"
        let no = NSButton(title: "Nur diesmal", target: self, action: #selector(decline))
        for button in [yes, no] {
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            yes.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            yes.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10),
            yes.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            no.trailingAnchor.constraint(equalTo: yes.leadingAnchor, constant: -8),
            no.centerYAnchor.constraint(equalTo: yes.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func accept() { target?.accept() }
    @objc private func decline() { target?.dismiss() }
}
