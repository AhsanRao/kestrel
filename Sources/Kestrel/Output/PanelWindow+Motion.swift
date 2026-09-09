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

    /// Rolls back up into the top edge, the way it came.
    ///
    /// A shape that unrolls out of the notch and then fades where it stands has no way back to
    /// where it started, and the illusion that it *is* the notch goes with it. The curve is the
    /// entrance's control points reversed, so the path out retraces the path in.
    func rollUp() {
        guard let panel = self.panel, panel.isVisible else { return }
        stopLevelAnimation()
        frameAnimator?.stop()
        isLeaving = true
        let settled = panel.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.64, 0, 0.78, 0)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(NSRect(x: settled.minX, y: settled.maxY - 1,
                                             width: settled.width, height: 1), display: true)
        } completionHandler: { [weak self] in
            // Only if it is still leaving: a question asked inside the exit calls it off, and
            // ordering the window out here would take the answer to it off the screen.
            guard let self, self.isLeaving, let panel = self.panel else { return }
            self.isLeaving = false
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.setFrame(settled, display: false)
        }
    }

    /// Calls off an exit in progress, leaving the window where it is and fully opaque. Retargeting
    /// with no duration is what stops the animations already running.
    func cancelRollUp(_ panel: NSPanel) {
        guard isLeaving else { return }
        isLeaving = false
        let current = panel.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
            panel.animator().setFrame(current, display: false)
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
