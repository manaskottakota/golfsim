//
//  ClubPickerView.swift
//  golfsim
//

import SwiftUI

struct ClubPickerView: View {
    @Bindable var clubSelection: ClubSelectionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT CLUB")
                .font(.caption.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.72))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GolfClub.allCases) { club in
                        Button {
                            clubSelection.selectedClub = club
                        } label: {
                            Text(club.shortName)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(clubSelection.selectedClub == club ? .black : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .background(
                                    clubSelection.selectedClub == club
                                        ? Color.accentColor
                                        : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                                .overlay {
                                    if clubSelection.selectedClub == club {
                                        Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(club.displayName)
                        .accessibilityAddTraits(clubSelection.selectedClub == club ? .isSelected : [])
                    }
                }
            }
            Text(clubSelection.selectedClub.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10)) }
    }
}

#Preview {
    ClubPickerView(clubSelection: ClubSelectionStore())
        .padding()
}
