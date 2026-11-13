//
//  RootView.swift
//  Tiny Pool
//

import SwiftUI

struct RootView: View {
    enum Screen { case home, game }

    @State private var game = PoolGame()
    @State private var screen = Screen.home

    var body: some View {
        FullWidth {
            screens
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        // Let the picture show right up to the top of the window, instead of a solid title bar.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
    }

    private var screens: some View {
        ZStack {
            switch screen {
            case .home:
                HomeView(game: game) { mode in
                    game.newGame(mode)
                    screen = .game
                }
                .transition(.opacity)
            case .game:
                GameView(game: game) {
                    screen = .home
                    // Reset only once the table has faded out, so a fresh rack is never seen on the way to the menu.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        if screen == .home { game.leave() }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
