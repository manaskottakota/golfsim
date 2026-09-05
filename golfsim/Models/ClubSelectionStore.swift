//
//  ClubSelectionStore.swift
//  golfsim
//

import Foundation
import Observation

@MainActor
@Observable
final class ClubSelectionStore {
    private static let storageKey = "com.manaskottakota.golfsim.selectedClub"

    var selectedClub: GolfClub {
        didSet { persist() }
    }

    init(selectedClub: GolfClub? = nil) {
        if let selectedClub {
            self.selectedClub = selectedClub
        } else if
            let raw = UserDefaults.standard.string(forKey: Self.storageKey),
            let club = GolfClub(rawValue: raw)
        {
            self.selectedClub = club
        } else {
            self.selectedClub = .sevenIron
        }
    }

    private func persist() {
        UserDefaults.standard.set(selectedClub.rawValue, forKey: Self.storageKey)
    }
}
