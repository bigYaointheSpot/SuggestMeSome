//
//  DSDivider.swift
//  SuggestMeSome
//
//  Hairline divider introduced in Feature 22 Prompt 2. Pulls width and
//  opacity from DSTokens so dividers stay visually consistent across
//  light/dark + accessibility contrast modes.
//

import SwiftUI

struct DSDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(DSOpacity.divider))
            .frame(height: DSHairline.width)
    }
}
