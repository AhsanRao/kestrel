import AppKit

/// How the island moves: arriving, leaving, and breathing while it records.
extension PanelWindow {
    /// Arrives by unrolling out of the top edge: the frame starts at zero height, flush with the
    /// screen, and grows down to its own size. Nothing slides in from off screen, because the notch
    /// it is pretending to be never went anywhere.
    func animateIn(_ panel: NSPanel) {
        let settled = panel.frame
        panel.setFrame(NSRect(x: settled.minX, y: settled.maxY - 1, width: settled.width, height: 1),
                       display: false)
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(settled, display: true)
        } completionHandler: { [weak self] in
            self?.isPlacing = false
        }
    }

    /// Fades out when it is leaving of its own accord, rather than blinking off.
    func fadeOut() {
        guard let panel = self.panel, panel.isVisible else { return }
        stopLevelAnimation()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, let panel = self.panel, panel.alphaValue < 0.05 else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }
    /// Cheap breathing animation while recording; no audio metering, so no extra tap on the input.
    func startLevelAnimation() {
        guard levelTimer == nil else { return }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.model.isRecording else { self.model.levelPhase = 0; return }
            self.model.levelPhase = self.model.levelPhase > 0.5 ? 0 : 1
        }
    }

    func stopLevelAnimation() {
        levelTimer?.invalidate()
        levelTimer = nil
        model.levelPhase = 0
    }
}
