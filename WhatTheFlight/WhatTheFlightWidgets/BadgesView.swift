//
//  BadgesView.swift
//  WhatTheFlightWidgets
//
//  The Badges widget's faces: one badge's ring filling toward its next level, what's next
//  up, what you earned lately and, on iPad's extra large size, every badge as a trophy case.
//  Tapping a badge opens its page in the logbook. Also compiled into the app for its DEBUG
//  widget gallery.
//

#if os(iOS)
import WidgetKit
import SwiftUI

struct BadgesView: View {
    let entry: LogbookEntry
    let family: WidgetFamily

    var body: some View {
        if let s = entry.snapshot, !s.badges.isEmpty, let hero = s.featuredBadge(entry.badgeID) {
            content(s, hero: hero)
                .widgetURL(AppRouter.url(for: family == .systemSmall || family.isAccessory ? .badge(hero.id) : .logbookTab("badges")))
        } else {
            empty.widgetURL(AppRouter.url(for: .logbook))
        }
    }

    @ViewBuilder
    private func content(_ s: LogbookSnapshot, hero: LogbookSnapshot.Badge) -> some View {
        switch family {
        case .accessoryInline: inline(hero)
        case .accessoryCircular: circular(hero)
        case .accessoryRectangular: rectangular(hero)
        case .systemMedium: medium(s, hero: hero)
        case .systemLarge: large(s, hero: hero)
        case .systemExtraLarge: extraLarge(s, hero: hero)
        default: small(s, hero: hero)
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryInline: Text("\(Image(systemName: "medal")) Badges")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "medal").font(.system(size: 20, weight: .semibold))
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Badges", systemImage: "medal").font(.mono(13, .bold))
                Text("Open What The Flight? to start").font(.mono(11))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            LogbookWidgetEmpty(snapshot: entry.snapshot, symbol: "medal", compact: family == .systemSmall)
        }
    }

    /// The badges closest to their next level besides the hero, topped up with any still to
    /// earn when there aren't enough.
    private func alsoClose(_ s: LogbookSnapshot, excluding hero: LogbookSnapshot.Badge, limit: Int) -> [LogbookSnapshot.Badge] {
        let next = s.nextUpBadges.filter { $0.id != hero.id }
        let more = s.badges
            .filter { b in b.id != hero.id && !b.isMaxed && !b.isRecord && !next.contains { $0.id == b.id } }
            .sorted { $0.fraction > $1.fraction }
        return Array((next + more).prefix(limit))
    }

    /// The hero's own caption: why it's the one shown.
    private func heroCaption(_ hero: LogbookSnapshot.Badge) -> LocalizedStringKey {
        if entry.badgeID == hero.id { return hero.isTopLevel ? "Every level" : "Following" }
        return hero.isUnlocked && hero.isMaxed ? "Badge" : "Next up"
    }

    // MARK: Lock Screen

    private func inline(_ hero: LogbookSnapshot.Badge) -> some View {
        Text("\(Image(systemName: hero.symbol)) \(hero.title) · \(hero.statusText)")
    }

    private func circular(_ hero: LogbookSnapshot.Badge) -> some View {
        Gauge(value: hero.fraction) {
            EmptyView()
        } currentValueLabel: {
            Image(systemName: hero.symbol)
                .font(.system(size: 18, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel(hero.accessibilityText)
    }

    private func rectangular(_ hero: LogbookSnapshot.Badge) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: hero.symbol)
                Text(hero.title).font(.mono(13, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .widgetAccentable()
            Gauge(value: hero.fraction) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            HStack {
                Text(hero.statusText).font(.mono(10, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if hero.hasLevels && hero.isUnlocked {
                    Text("L\(hero.level)/\(hero.levels)").font(.mono(10, .bold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Home Screen

    private func small(_ s: LogbookSnapshot, hero: LogbookSnapshot.Badge) -> some View {
        VStack(spacing: 0) {
            HStack {
                WidgetCaption(heroCaption(hero), color: hero.isUnlocked ? Palette.notable : Palette.caption)
                Spacer(minLength: 2)
                Text("\(s.unlockedCount)/\(s.badges.count)")
                    .font(.mono(9, .bold))
                    .foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 4)
            BadgeMedal(badge: hero, size: 62)
            Spacer(minLength: 6)
            Text(hero.title)
                .font(.mono(13, .heavy))
                .foregroundStyle(Palette.value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 5) {
                if hero.hasLevels { LevelPips(earned: hero.level, total: hero.levels, size: 5) }
                Text(hero.statusText)
                    .font(.mono(9, .semibold))
                    .foregroundStyle(hero.isUnlocked ? Palette.notable : Palette.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hero.accessibilityText)
    }

    private func medium(_ s: LogbookSnapshot, hero: LogbookSnapshot.Badge) -> some View {
        let others = alsoClose(s, excluding: hero, limit: 3)
        return HStack(alignment: .top, spacing: 14) {
            Link(destination: AppRouter.url(for: .badge(hero.id))) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetCaption(heroCaption(hero), color: hero.isUnlocked ? Palette.notable : Palette.caption)
                    Spacer(minLength: 4)
                    BadgeMedal(badge: hero, size: 56)
                        .padding(.leading, hero.isTopLevel ? 5 : 0)
                    Spacer(minLength: 6)
                    Text(hero.title)
                        .font(.mono(13, .heavy))
                        .foregroundStyle(Palette.value)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(hero.statusText)
                        .font(.mono(9, .semibold))
                        .foregroundStyle(hero.isUnlocked ? Palette.notable : Palette.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ProgressCapsule(fraction: hero.fraction, tint: hero.isUnlocked ? Palette.notable : Palette.route, height: 4)
                        .padding(.top, 5)
                }
                .frame(width: 118, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 7) {
                SummaryHeader(snapshot: s)
                ForEach(others) { badge in
                    Link(destination: AppRouter.url(for: .badge(badge.id))) {
                        BadgeRow(badge: badge, size: 26)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func large(_ s: LogbookSnapshot, hero: LogbookSnapshot.Badge) -> some View {
        let next = alsoClose(s, excluding: hero, limit: 3)
        let recent = Array(s.recentBadges.prefix(3))
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                WidgetCaption("Badges", color: Palette.notable)
                Spacer()
                Text("\(s.unlockedCount) of \(s.badges.count) earned")
                    .font(.mono(10, .bold))
                    .foregroundStyle(Palette.caption)
            }

            Link(destination: AppRouter.url(for: .badge(hero.id))) {
                HStack(spacing: 14) {
                    BadgeMedal(badge: hero, size: 70)
                        .padding(hero.isTopLevel ? 6 : 0)
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetCaption(heroCaption(hero), color: hero.isUnlocked ? Palette.notable : Palette.caption)
                        Text(hero.title)
                            .font(.mono(17, .heavy))
                            .foregroundStyle(Palette.value)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !hero.detail.isEmpty {
                            Text(hero.detail)
                                .font(.mono(9))
                                .foregroundStyle(Palette.caption)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ProgressCapsule(fraction: hero.fraction, tint: hero.isUnlocked ? Palette.notable : Palette.route, height: 5)
                            .padding(.top, 2)
                        HStack(spacing: 6) {
                            if hero.hasLevels { LevelPips(earned: hero.level, total: hero.levels, size: 5) }
                            Text(hero.statusText)
                                .font(.mono(9, .bold))
                                .foregroundStyle(hero.isUnlocked ? Palette.notable : Palette.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }

            if !next.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetCaption("Also close")
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(next) { badge in
                            Link(destination: AppRouter.url(for: .badge(badge.id))) {
                                VStack(spacing: 4) {
                                    BadgeMedal(badge: badge, size: 38)
                                    Text(badge.title)
                                        .font(.mono(8, .bold))
                                        .foregroundStyle(Palette.value)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(badge.statusText)
                                        .font(.mono(7, .medium))
                                        .foregroundStyle(Palette.caption)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetCaption("Recently earned")
                    ForEach(recent) { badge in
                        Link(destination: AppRouter.url(for: .badge(badge.id))) {
                            EarnedRow(badge: badge, now: entry.date)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 8) {
                ForEach(s.groups, id: \.id) { group in
                    GroupTally(title: group.title, badges: group.badges, compact: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// iPad: the hero and each group's tally on the left, every badge on the right.
    private func extraLarge(_ s: LogbookSnapshot, hero: LogbookSnapshot.Badge) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetCaption("Badges", color: Palette.notable)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(s.unlockedCount)")
                        .font(.mono(30, .heavy))
                        .foregroundStyle(Palette.notable)
                        .widgetAccentable()
                    Text("of \(s.badges.count)")
                        .font(.mono(13, .bold))
                        .foregroundStyle(Palette.caption)
                }
                VStack(alignment: .leading, spacing: 3) {
                    ProgressCapsule(fraction: Double(s.levelsEarned) / Double(max(1, s.levelsTotal)), height: 5)
                    Text("\(s.levelsEarned) of \(s.levelsTotal) levels")
                        .font(.mono(8, .semibold))
                        .foregroundStyle(Palette.caption)
                }
                Link(destination: AppRouter.url(for: .badge(hero.id))) {
                    HStack(spacing: 10) {
                        BadgeMedal(badge: hero, size: 46)
                            .padding(hero.isTopLevel ? 4 : 0)
                        VStack(alignment: .leading, spacing: 2) {
                            WidgetCaption(heroCaption(hero), color: hero.isUnlocked ? Palette.notable : Palette.caption)
                            Text(hero.title)
                                .font(.mono(12, .heavy))
                                .foregroundStyle(Palette.value)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(hero.statusText)
                                .font(.mono(8, .semibold))
                                .foregroundStyle(Palette.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(s.groups, id: \.id) { group in
                        GroupTally(title: group.title, badges: group.badges)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 186, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            TrophyCase(groups: s.groups, highlighted: hero.id)
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        self == .accessoryInline || self == .accessoryCircular || self == .accessoryRectangular
    }
}

// MARK: - Pieces

/// "17 of 46 badges" over a bar of every level earned.
private struct SummaryHeader: View {
    let snapshot: LogbookSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                WidgetCaption("Also close")
                Spacer(minLength: 2)
                Text("\(snapshot.unlockedCount)/\(snapshot.badges.count) earned")
                    .font(.mono(8, .bold))
                    .foregroundStyle(Palette.faint)
            }
            ProgressCapsule(fraction: Double(snapshot.levelsEarned) / Double(max(1, snapshot.levelsTotal)), height: 3)
        }
    }
}

/// A badge's medal, title and progress on one line.
private struct BadgeRow: View {
    let badge: LogbookSnapshot.Badge
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: 8) {
            BadgeMedal(badge: badge, size: size)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(badge.title)
                        .font(.mono(10, .bold))
                        .foregroundStyle(Palette.value)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text(badge.statusText)
                        .font(.mono(8, .semibold))
                        .foregroundStyle(Palette.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                ProgressCapsule(fraction: badge.fraction, tint: badge.isUnlocked ? Palette.notable : Palette.route, height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.accessibilityText)
    }
}

/// "Round the Clock · Level 4 · 2 days ago · by DL570".
private struct EarnedRow: View {
    let badge: LogbookSnapshot.Badge
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            BadgeMedal(badge: badge, size: 24)
                .padding(badge.isTopLevel ? 2 : 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(badge.title)
                    .font(.mono(10, .bold))
                    .foregroundStyle(Palette.value)
                    .lineLimit(1)
                Text(detail)
                    .font(.mono(8))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let level = badge.levelText { parts.append(level) }
        if let date = badge.unlockedAt {
            parts.append(Calendar.current.isDate(date, inSameDayAs: now)
                         ? String(localized: "today")
                         : date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        }
        if let by = badge.unlockedBy { parts.append(String(localized: "by \(by)")) }
        return parts.joined(separator: " · ")
    }
}

/// A group's name over a bar of its levels earned; `compact` stacks the count under the
/// name, for five across.
private struct GroupTally: View {
    let title: String
    let badges: [LogbookSnapshot.Badge]
    var compact = false

    var body: some View {
        let earned = badges.reduce(0) { $0 + $1.level }
        let total = max(1, badges.reduce(0) { $0 + $1.levels })
        let count = Text("\(badges.filter(\.isUnlocked).count)/\(badges.count)")
            .font(.mono(compact ? 7 : 8, .bold))
            .foregroundStyle(Palette.faint)
        let name = Text(title)
            .font(.mono(compact ? 7 : 8, .bold))
            .textCase(.uppercase)
            .foregroundStyle(Palette.caption)
        VStack(alignment: .leading, spacing: 2) {
            if compact {
                name.lineLimit(1).minimumScaleFactor(0.7)
                count
            } else {
                HStack {
                    name
                    Spacer()
                    count
                }
            }
            ProgressCapsule(fraction: Double(earned) / Double(total), height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Every badge, a row per group, sized to fill the space.
private struct TrophyCase: View {
    let groups: [(id: String, title: String, badges: [LogbookSnapshot.Badge])]
    let highlighted: String

    var body: some View {
        GeometryReader { geo in
            let columns = CGFloat(max(1, groups.map(\.badges.count).max() ?? 1))
            let rows = CGFloat(max(1, groups.count))
            let caption: CGFloat = 13
            let gap: CGFloat = 6
            let byWidth = (geo.size.width - gap * (columns - 1)) / columns
            let byHeight = (geo.size.height - rows * caption - gap * (rows - 1)) / rows
            let size = max(14, min(byWidth, byHeight) * 0.86)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(groups, id: \.id) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(.mono(8, .bold))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.caption)
                            .frame(height: caption - 2, alignment: .bottom)
                        HStack(spacing: gap) {
                            ForEach(group.badges) { badge in
                                Link(destination: AppRouter.url(for: .badge(badge.id))) {
                                    BadgeMedal(badge: badge, size: size)
                                        .frame(width: byWidth, height: size / 0.86)
                                        .background {
                                            if badge.id == highlighted {
                                                Circle().fill(Palette.ink.opacity(0.08)).frame(width: size * 1.18, height: size * 1.18)
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Every badge")
        .accessibilityValue(groups.map { group in
            "\(group.title): \(group.badges.filter(\.isUnlocked).count) of \(group.badges.count)"
        }.joined(separator: ", "))
    }
}
#endif
