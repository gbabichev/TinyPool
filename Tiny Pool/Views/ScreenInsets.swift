//
//  ScreenInsets.swift
//  Tiny Pool
//
//  Screens centre their content on the whole display, not on the safe area, so nothing looks
//  off-centre next to a big gutter (the iPhone Duo has a wide one beside the camera). The real
//  safe-area insets are passed down so that corner buttons can still keep clear of the gutter.
//  This applies in portrait too: the Duo folded keeps its strip down one side even upright.
//

import SwiftUI

extension EnvironmentValues {
    /// The safe-area insets of the display, as reported before the screens ignored them sideways.
    @Entry var screenInsets = EdgeInsets()
}

/// Lays `content` out across the full width of the display and hands it the safe-area insets.
struct FullWidth<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            content
                .environment(\.screenInsets, EdgeInsets(
                    top: geo.safeAreaInsets.top,
                    leading: geo.safeAreaInsets.leading,
                    bottom: geo.safeAreaInsets.bottom,
                    trailing: geo.safeAreaInsets.trailing))
                .ignoresSafeArea(.container, edges: .horizontal)
        }
    }
}
