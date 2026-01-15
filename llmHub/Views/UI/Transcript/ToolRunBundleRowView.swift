//
//  ToolRunBundleRowView.swift
//  llmHub
//
//  Grouped tool run bundle row for transcript rendering.
//

import SwiftUI

struct ToolRunBundleRowView: View {
    let bundle: ToolRunBundleViewModel

    var body: some View {
        ToolRunBundleCardView(bundle: bundle)
    }
}
