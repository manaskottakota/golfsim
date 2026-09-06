//
//  ClubPickerView.swift
//  golfsim
//

import SwiftUI

struct ClubPickerView: View {
    @Bindable var clubSelection: ClubSelectionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Club")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GolfClub.allCases) { club in
                        Button {
                            clubSelection.selectedClub = club
                        } label: {
                            Text(club.shortName)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    clubSelection.selectedClub == club
                                        ? Color.accentColor.opacity(0.2)
                                        : Color(.secondarySystemFill),
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
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ClubPickerView(clubSelection: ClubSelectionStore())
        .padding()
}
