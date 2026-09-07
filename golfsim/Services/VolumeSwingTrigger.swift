//
//  VolumeSwingTrigger.swift
//  golfsim
//

import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Fires when the user presses hardware Volume Up while the app is active.
@MainActor
@Observable
final class VolumeSwingTrigger {
    private(set) var isEnabled = false

    var onVolumeUp: (() -> Void)?

    private var volumeView: MPVolumeView?
    private var observation: NSKeyValueObservation?
    private var lastVolume: Float = 0
    private var isAdjustingProgrammatically = false

    func enable() {
        guard !isEnabled else { return }

        configureAudioSessionIfNeeded()

        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.clipsToBounds = true
        view.alpha = 0.01
        attachVolumeView(view)

        volumeView = view
        lastVolume = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self else { return }
            Task { @MainActor in
                self.handleVolumeChange(change.newValue)
            }
        }

        isEnabled = true
    }

    func disable() {
        observation?.invalidate()
        observation = nil
        volumeView?.removeFromSuperview()
        volumeView = nil
        isEnabled = false
    }

    private func configureAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func attachVolumeView(_ view: MPVolumeView) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return }
        window.addSubview(view)
    }

    private func handleVolumeChange(_ newValue: NSNumber?) {
        guard isEnabled, !isAdjustingProgrammatically, let newValue else { return }
        let volume = newValue.floatValue

        if volume > lastVolume {
            onVolumeUp?()
        }

        lastVolume = volume

        // Reset volume so repeated Volume Up presses can fire again.
        isAdjustingProgrammatically = true
        setSystemVolume(min(max(lastVolume - 0.05, 0), 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isAdjustingProgrammatically = false
            self?.lastVolume = AVAudioSession.sharedInstance().outputVolume
        }
    }

    private func setSystemVolume(_ value: Float) {
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = value
    }
}
