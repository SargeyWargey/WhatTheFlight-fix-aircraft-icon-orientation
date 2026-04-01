//
//  iOSComponents.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import SwiftUI

#if os(iOS)
import UIKit

// MARK: - Haptic Feedback Helper

struct HapticFeedback {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - iOS-Specific Button Styles

/// Touch-optimized button style for iOS with haptic feedback
struct TouchOptimizedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - iOS-Specific Layout Components

/// iOS-specific adaptive layout container
struct AdaptiveContainer<Content: View>: View {
    let content: Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        if horizontalSizeClass == .compact && verticalSizeClass == .regular {
            // iPhone portrait
            VStack {
                content
            }
        } else if horizontalSizeClass == .regular && verticalSizeClass == .compact {
            // iPhone landscape or iPad landscape
            HStack {
                content
            }
        } else {
            // iPad portrait or other configurations
            VStack {
                content
            }
        }
    }
}

/// iOS-specific pull-to-refresh functionality
struct PullToRefreshView<Content: View>: View {
    let content: Content
    let onRefresh: () -> Void
    
    init(onRefresh: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onRefresh = onRefresh
        self.content = content()
    }
    
    var body: some View {
        ScrollView {
            content
                .frame(minHeight: UIScreen.main.bounds.height)
        }
        .scrollDisabled(false)
        .refreshable {
            onRefresh()
        }
    }
}


#endif