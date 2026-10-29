//
//  LogbookBadgesTab.swift
//  WhatTheFlight
//
//  Badges on iPhone and iPad: how many are unlocked, the ones closest to done, the latest
//  earned, then every badge by group (Milestones, Rare Birds, Moments, Collections). Tap one
//  for its page; swipe between pages.
//

#if os(iOS)
import SwiftUI

struct LogbookBadgesTab: View {
    let ctx: LogbookContext

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let digest = ctx.logbook.digest
        let columns = sizeClass == .regular ? 6 : 4
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summary(digest)

                let next = digest.nextUp()
                if !next.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        LogbookHeader("Next up")
                        VStack(spacing: 0) {
                            ForEach(Array(next.enumerated()), id: \.element.id) { i, a in
                                if i > 0 { Divider() }
                                NavigationLink(value: LogbookRoute.badge(a.id)) { NextUpRow(achievement: a) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                let recent = digest.recentlyUnlocked()
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        LogbookHeader("Recently unlocked")
                        // Top-aligned, equal-height cards: a title that wraps grows downward
                        // and the rings stay level.
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(recent) { a in
                                NavigationLink(value: LogbookRoute.badge(a.id)) {
                                    VStack(spacing: 6) {
                                        AchievementBadge(achievement: a)
                                        if let at = a.unlockedAt {
                                            Text(LogbookGrouping.shortTitle(for: at))
                                                .monoScaled(9, .semibold)
                                                .foregroundStyle(Palette.caption)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .padding(.vertical, 12)
                                    .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(Achievement.Group.allCases, id: \.self) { group in
                    let badges = digest.achievements.filter { $0.group == group }
                    VStack(alignment: .leading, spacing: 12) {
                        LogbookHeader(title: LocalizedStringKey(group.title)) {
                            Text("\(badges.filter(\.isUnlocked).count) of \(badges.count)").foregroundStyle(Palette.caption)
                        }
                        // Top-aligned so a title that wraps grows downward and the rings in a
                        // row stay level.
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: columns), spacing: 16) {
                            ForEach(badges) { a in
                                NavigationLink(value: LogbookRoute.badge(a.id)) {
                                    AchievementBadge(achievement: a)
                                        .frame(maxWidth: .infinity, alignment: .top)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        // Four badges a row: past this their titles no longer fit.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                }
            }
            .padding(sizeClass == .regular ? 24 : 16)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(LogbookBackdrop())
    }

    private func summary(_ digest: LogbookDigest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(digest.unlockedCount) of \(digest.achievements.count) unlocked")
                    .monoScaled(22, .heavy)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if digest.levelsToGo > 0 {
                    Text("\(digest.levelsToGo) levels to go")
                        .monoScaled(11, .semibold)
                        .foregroundStyle(Palette.caption)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.12))
                    Capsule().fill(Palette.notable)
                        .frame(width: max(8, geo.size.width * Double(digest.unlockedCount) / Double(max(1, digest.achievements.count))))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Badge pages: swipe left and right through every badge; Back returns to the logbook.
struct AchievementPager: View {
    let achievements: [Achievement]
    @State var selection: String
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(achievements) { achievement in
                AchievementDetailView(achievement: achievement, logbook: logbook, onTrack: onTrack, isLive: isLive)
                    .tag(achievement.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(LogbookBackdrop())
        .navigationTitle(achievements.first { $0.id == selection }?.title ?? "Badge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(achievements.first { $0.id == selection }?.title ?? "Badge")
                        .monoScaled(15, .bold)
                    if let index = achievements.firstIndex(where: { $0.id == selection }) {
                        Text("\(index + 1) of \(achievements.count) · \(achievements[index].group.title)")
                            .monoScaled(10)
                            .foregroundStyle(Palette.caption)
                    }
                }
            }
        }
    }
}

struct AchievementDetailView: View {
    let achievement: Achievement
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }

    @Environment(\.favoriteAircraft) private var favorites

    var body: some View {
        let a = achievement
        List {
            Section {
                VStack(spacing: 10) {
                    AchievementBadge(achievement: a, scale: 2.2, showsTitle: false)
                        .padding(.vertical, 8)
                    if a.hasLevels {
                        TierDots(earned: a.level, total: a.tiers.count, scale: 1.8)
                    }
                    Text(a.isMaxed ? (a.hasLevels ? "EVERY LEVEL" : "UNLOCKED") : (a.isUnlocked ? "LEVEL \(a.level)" : "LOCKED"))
                        .monoScaled(11, .heavy)
                        .tracking(3)
                        .foregroundStyle(a.isUnlocked ? Palette.notable : Palette.caption)
                    Text(a.title)
                        .monoScaled(26, .heavy)
                        .foregroundStyle(Palette.ink)
                    Text(a.detail)
                        .monoScaled(14, .semibold)
                        .foregroundStyle(Palette.value)
                        .multilineTextAlignment(.center)
                    Text(a.about)
                        .monoScaled(12)
                        .foregroundStyle(Palette.caption)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                AchievementProgress(achievement: a)
                    .padding(.vertical, 6)
            }
            Section(a.examples.isEmpty ? "No aircraft yet" : "Aircraft that count") {
                if a.examples.isEmpty {
                    Text("Keep the radar running — anything that qualifies shows up here.")
                        .monoScaled(12)
                        .foregroundStyle(Palette.caption)
                }
                ForEach(a.examples) { s in
                    NavigationLink {
                        SightingDetailView(sighting: s, logbook: logbook, onTrack: onTrack, isLive: isLive(s.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(s.displayIdentifier).monoScaled(15, .bold)
                                    .foregroundStyle(favorites.contains(s) ? Palette.favoriteText : Palette.ink)
                                if favorites.contains(s) {
                                    Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.favorite)
                                        .accessibilityLabel("Favorite")
                                }
                                if let route = s.routeText {
                                    Text(route).monoScaled(11, .semibold).foregroundStyle(Palette.route)
                                }
                                if s.id == a.unlockedBy?.id {
                                    Image(systemName: "star.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.notable)
                                        .accessibilityLabel("Unlocked it")
                                }
                            }
                            Text("\(s.summaryLine) · \(s.firstSeen.formatted(date: .abbreviated, time: .shortened))")
                                .monoScaled(11)
                                .foregroundStyle(Palette.caption)
                                .lineLimit(1)
                        }
                    }
                }
                if a.examples.count >= Achievement.exampleLimit {
                    Text("Showing the latest \(a.examples.count)")
                        .monoScaled(11)
                        .foregroundStyle(Palette.caption)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LogbookBackdrop())
        .fontDesign(.monospaced)
    }
}
#endif
