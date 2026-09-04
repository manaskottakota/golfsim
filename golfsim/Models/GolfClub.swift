//
//  GolfClub.swift
//  golfsim
//

import Foundation

enum GolfClub: String, CaseIterable, Identifiable, Codable, Sendable {
    case driver
    case threeWood = "3_wood"
    case fiveWood = "5_wood"
    case hybrid
    case fourIron = "4_iron"
    case fiveIron = "5_iron"
    case sixIron = "6_iron"
    case sevenIron = "7_iron"
    case eightIron = "8_iron"
    case nineIron = "9_iron"
    case pitchingWedge = "pitching_wedge"
    case gapWedge = "gap_wedge"
    case sandWedge = "sand_wedge"
    case lobWedge = "lob_wedge"
    case putter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .driver: "Driver"
        case .threeWood: "3 Wood"
        case .fiveWood: "5 Wood"
        case .hybrid: "Hybrid"
        case .fourIron: "4 Iron"
        case .fiveIron: "5 Iron"
        case .sixIron: "6 Iron"
        case .sevenIron: "7 Iron"
        case .eightIron: "8 Iron"
        case .nineIron: "9 Iron"
        case .pitchingWedge: "Pitching Wedge"
        case .gapWedge: "Gap Wedge"
        case .sandWedge: "Sand Wedge"
        case .lobWedge: "Lob Wedge"
        case .putter: "Putter"
        }
    }

    var shortName: String {
        switch self {
        case .driver: "DR"
        case .threeWood: "3W"
        case .fiveWood: "5W"
        case .hybrid: "HY"
        case .fourIron: "4i"
        case .fiveIron: "5i"
        case .sixIron: "6i"
        case .sevenIron: "7i"
        case .eightIron: "8i"
        case .nineIron: "9i"
        case .pitchingWedge: "PW"
        case .gapWedge: "GW"
        case .sandWedge: "SW"
        case .lobWedge: "LW"
        case .putter: "PT"
        }
    }
}
