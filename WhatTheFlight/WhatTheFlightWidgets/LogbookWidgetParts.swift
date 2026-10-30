//
//  LogbookWidgetParts.swift
//  WhatTheFlightWidgets
//
//  Pieces the logbook widgets (Logbook, Badges, Your Sky) share: the timeline entry, the
//  backdrop, captions, badge medals, the day bars, the 24-hour dial and the heading rose,
//  and the sample logbook the widget gallery shows. Everything reads `LogbookSnapshot`,
//  which the app writes to the App Group (`LogbookWidgetPublisher`). Also compiled into the
//  app for its DEBUG widget gallery (`WidgetGallery`).
//

#if os(iOS)
import WidgetKit
import SwiftUI

struct LogbookEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has written one (it does on launch).
    let snapshot: LogbookSnapshot?
    /// The badge the Badges widget follows; nil = the one closest to its next level.
    var badgeID: String? = nil
}

extension LogbookSnapshot {
    /// What the app last shared, in the units it's set to.
    static func shared() -> LogbookSnapshot? {
        Units.reload()
        return SharedRadarStore().logbook
    }

    /// Midnight after `date`: today's count and the streak move on.
    static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(86_400)
    }
}

/// Hands a widget's family to its face, which takes it as a value so the app's gallery can
/// draw every size (`widgetFamily` can't be set from outside).
struct WidgetFamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: (WidgetFamily) -> Content

    var body: some View { content(family) }
}

// MARK: - Backdrop and type

/// The paper, with a radar's range rings fanning faintly out of one corner.
struct LogbookWidgetBackdrop: View {
    var corner: UnitPoint = .topTrailing

    var body: some View {
        ZStack {
            Palette.paper
            Canvas { context, size in
                let centre = CGPoint(x: corner.x * size.width, y: corner.y * size.height)
                let step = max(size.width, size.height) / 7
                for i in 1...9 {
                    let r = step * CGFloat(i)
                    context.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                                   with: .color(Palette.ink.opacity(i % 3 == 0 ? 0.09 : 0.05)), lineWidth: i % 3 == 0 ? 1 : 0.6)
                }
            }
        }
    }
}

/// "LOGBOOK", "NEXT UP": the small capitals over every block.
struct WidgetCaption: View {
    let text: LocalizedStringKey
    var color: Color = Palette.caption

    init(_ text: LocalizedStringKey, color: Color = Palette.caption) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.mono(9, .bold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// "🔥 5": the streak, coral while it's alive, faint once it's lapsed.
struct StreakChip: View {
    let days: Int
    /// Alive, but nothing's logged yet today.
    var atRisk = false
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.9, weight: .bold))
            Text("\(days)")
                .font(.mono(size, .heavy))
                .monospacedDigit()
        }
        .foregroundStyle(days == 0 ? Palette.faint : atRisk ? ChartTone.amber.color : ChartTone.coral.color)
        .padding(.horizontal, size * 0.55)
        .padding(.vertical, size * 0.22)
        .background(Capsule().fill((days == 0 ? Palette.faint : ChartTone.coral.color).opacity(0.14)))
        .widgetAccentable()
        .accessibilityLabel(days == 1 ? "1 day streak" : "\(days) day streak")
    }
}

// MARK: - Badges

/// A badge as the logbook draws it: its symbol in a progress ring, gold once earned, a filled
/// disc and an outer ring when every level is.
struct BadgeMedal: View {
    let badge: LogbookSnapshot.Badge
    var size: CGFloat = 54

    var body: some View {
        let line = max(2.5, size * 0.075)
        ZStack {
            if badge.isTopLevel {
                Circle().fill(Palette.notable.opacity(0.18))
            } else if badge.isUnlocked {
                Circle().fill(Palette.notable.opacity(0.07))
            }
            Circle()
                .stroke(Palette.ink.opacity(0.12), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.015, badge.fraction))
                .stroke(badge.isUnlocked ? Palette.notable : Palette.route, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Image(systemName: badge.symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(badge.isUnlocked ? Palette.notable : Palette.faint)
                .widgetAccentable(badge.isUnlocked)
        }
        .frame(width: size, height: size)
        .overlay {
            if badge.isTopLevel {
                Circle()
                    .stroke(Palette.notable, lineWidth: max(1, size * 0.028))
                    .padding(-size * 0.09)
            }
        }
        .accessibilityHidden(true)
    }
}

/// ●●○ — levels earned of a badge's levels.
struct LevelPips: View {
    let earned: Int
    let total: Int
    var size: CGFloat = 5

    var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < earned ? Palette.notable : Color.clear)
                    .overlay(Circle().stroke(i < earned ? Palette.notable : Palette.faint, lineWidth: 1))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A thin capsule bar toward the next level.
struct ProgressCapsule: View {
    let fraction: Double
    var tint: Color = Palette.notable
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.12))
                Capsule().fill(tint)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

extension LogbookSnapshot.Badge {
    /// "Every level", "1,234 of 5,000", "Unlocked".
    var statusText: String {
        if isTopLevel { return String(localized: "Every level") }
        if !hasLevels && isUnlocked { return String(localized: "Unlocked") }
        return progressText
    }

    /// "Level 2 of 5", or nil for a one-off badge.
    var levelText: String? { hasLevels ? String(localized: "Level \(level) of \(levels)") : nil }

    var accessibilityText: String {
        [title, levelText, statusText, detail].compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - Days

/// Aircraft a day as bars, taller ones warmer, today in teal.
struct DayBars: View {
    let days: [LogbookSnapshot.DayCount]
    let today: Date
    var spacing: CGFloat = 3
    var labels = false

    var body: some View {
        let peak = Double(max(1, days.map(\.count).max() ?? 0))
        VStack(spacing: 3) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(days, id: \.day) { day in
                        let isToday = day.day == today
                        let fraction = Double(day.count) / peak
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(day.count == 0 ? Palette.ink.opacity(0.1)
                                  : isToday ? ChartTone.teal.color : Self.heat(fraction))
                            .frame(height: day.count == 0 ? 2 : max(3, geo.size.height * fraction))
                            .frame(maxWidth: .infinity)
                            .widgetAccentable(isToday)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if labels {
                HStack(spacing: spacing) {
                    ForEach(days, id: \.day) { day in
                        Text(day.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.mono(7, day.day == today ? .heavy : .medium))
                            .foregroundStyle(day.day == today ? ChartTone.teal.color : Palette.faint)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aircraft per day")
        .accessibilityValue(days.map { "\($0.day.formatted(.dateTime.weekday(.wide))) \($0.count)" }.joined(separator: ", "))
    }

    /// Violet at the baseline, pink, then amber at the top, as the logbook's count bars.
    static func heat(_ fraction: Double) -> Color {
        ChartTone.blend([(0, .violet), (0.5, .pink), (0.9, .amber)], fraction)
    }
}

// MARK: - Sky

/// The day as a 24-hour dial, midnight at the top: a bar per hour as long as the aircraft it
/// brings, coloured like the sky at that hour, and a hand at the time now.
struct SkyDial: View {
    let hourly: [Int]
    let now: Date
    /// Bars in the widget's tint only (Lock Screen).
    var monochrome = false

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = side / 2
            let inner = outer * 0.48
            let peak = CGFloat(max(1, hourly.max() ?? 0))
            let busiest = (hourly.max() ?? 0) > 0 ? hourly.firstIndex(of: Int(peak)) : nil
            let hour = Calendar.current.component(.hour, from: now)
            let minute = Calendar.current.component(.minute, from: now)
            let ink = monochrome ? Color.primary : Palette.ink

            let ring = inner - side * 0.035
            context.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)),
                           with: .color(ink.opacity(0.18)), lineWidth: 1)
            for (h, count) in hourly.enumerated() {
                let mid = Double(h) * 15 + 7.5 - 90
                let a0 = Angle.degrees(mid - 6.2), a1 = Angle.degrees(mid + 6.2)
                let length = count == 0 ? side * 0.015 : max(side * 0.04, (outer - inner) * CGFloat(count) / peak)
                var bar = Path()
                bar.addArc(center: c, radius: inner + length, startAngle: a0, endAngle: a1, clockwise: false)
                bar.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
                bar.closeSubpath()
                let colour: Color = monochrome ? .primary.opacity(h == hour ? 1 : 0.45)
                    : count == 0 ? ink.opacity(0.1) : ChartTone.timeOfDay(h)
                context.fill(bar, with: .color(colour))
                if h == busiest && !monochrome {
                    context.stroke(bar, with: .color(Palette.value.opacity(0.7)), lineWidth: 1.2)
                }
            }
            // Quarter ticks inside the ring: midnight, 6, noon, 18.
            for q in 0..<4 {
                let a = Angle.degrees(Double(q) * 90 - 90)
                let from = CGPoint(x: c.x + cos(a.radians) * (ring - side * 0.05), y: c.y + sin(a.radians) * (ring - side * 0.05))
                let to = CGPoint(x: c.x + cos(a.radians) * ring, y: c.y + sin(a.radians) * ring)
                var tick = Path()
                tick.move(to: from)
                tick.addLine(to: to)
                context.stroke(tick, with: .color(ink.opacity(0.35)), lineWidth: q == 0 ? 1.6 : 1)
            }
            // The hand: from the inner ring past the bars, ending in a dot.
            let a = Angle.degrees((Double(hour) + Double(minute) / 60) * 15 - 90)
            let tip = CGPoint(x: c.x + cos(a.radians) * (outer - side * 0.01), y: c.y + sin(a.radians) * (outer - side * 0.01))
            var hand = Path()
            hand.move(to: CGPoint(x: c.x + cos(a.radians) * ring, y: c.y + sin(a.radians) * ring))
            hand.addLine(to: tip)
            let handColour = monochrome ? Color.primary : Palette.signal
            context.stroke(hand, with: .color(handColour), style: StrokeStyle(lineWidth: max(1.2, side * 0.014), lineCap: .round))
            let dot = side * 0.026
            context.fill(Path(ellipseIn: CGRect(x: tip.x - dot, y: tip.y - dot, width: dot * 2, height: dot * 2)), with: .color(handColour))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aircraft by hour of the day")
    }
}

/// Which way they fly: 16 petals, area-true, coloured round the compass, north marked red.
struct HeadingRose: View {
    let sectors: [Int]

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = side * 0.42
            let peak = Double(max(1, sectors.max() ?? 1))
            for r in [0.5, 1.0] {
                let radius = outer * r
                context.stroke(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                               with: .color(Palette.ink.opacity(r == 1 ? 0.2 : 0.1)), lineWidth: 1)
            }
            for (i, count) in sectors.enumerated() where count > 0 {
                let radius = outer * sqrt(Double(count) / peak)
                let mid = Angle.degrees(Double(i) * 22.5 - 90)
                var petal = Path()
                petal.move(to: c)
                petal.addArc(center: c, radius: radius, startAngle: mid - .degrees(9.5), endAngle: mid + .degrees(9.5), clockwise: false)
                petal.closeSubpath()
                context.fill(petal, with: .color(ChartTone.heading(Double(i) * 22.5)))
            }
            context.draw(Text("N").font(.mono(max(7, side * 0.08), .heavy)).foregroundStyle(Palette.signal),
                         at: CGPoint(x: c.x, y: c.y - outer - side * 0.06))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Directions aircraft fly")
    }
}

// MARK: - Empty

/// Before the app has shared a logbook, or while it's still empty.
struct LogbookWidgetEmpty: View {
    let snapshot: LogbookSnapshot?
    var symbol = "book.closed"
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 20 : 26, weight: .light))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            Text(snapshot == nil ? "Open What The Flight?" : "Nothing logged yet")
                .font(.mono(compact ? 12 : 14, .bold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(snapshot == nil ? "Your logbook shows up here once the app has run." : "Every aircraft that flies over is logged on its own.")
                .font(.mono(compact ? 9 : 10))
                .foregroundStyle(Palette.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Sample

extension LogbookSnapshot {
    /// A busy logbook for the widget gallery and placeholders.
    static var sample: LogbookSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let pattern = [41, 28, 0, 36, 52, 47, 31, 18, 44, 39, 61, 58, 23, 35, 49, 27, 33, 0, 46, 54,
                       38, 29, 41, 57, 66, 42, 37, 25, 48, 53, 34, 44, 59, 38, 23]
        let days: [DayCount] = pattern.enumerated().compactMap { i, count in
            guard count > 0, let day = calendar.date(byAdding: .day, value: -(pattern.count - 1 - i), to: today) else { return nil }
            return DayCount(day: day, count: count)
        }
        func badge(_ id: String, _ title: String, _ group: String, _ symbol: String, level: Int, of levels: Int,
                   _ fraction: Double, _ progress: String, target: String = "", record: Bool = false, ago: Double? = nil) -> Badge {
            let groupTitle = ["milestones": "Milestones", "rareBirds": "Rare Birds", "moments": "Moments",
                              "collections": "Collections", "skyView": "Sky View"][group] ?? group
            return Badge(id: id, title: title, group: group, groupTitle: groupTitle, symbol: symbol,
                         detail: "", level: level, levels: levels, fraction: fraction, progressText: progress,
                         targetLabel: target, isRecord: record,
                         unlockedAt: ago.map { Date().addingTimeInterval(-$0 * 86_400) }, unlockedBy: ago == nil ? nil : "DL570")
        }
        let badges = [
            badge("first", "First Contact", "milestones", "airplane", level: 1, of: 1, 1, "1 of 1", ago: 200),
            badge("spotter", "Plane Spotter", "milestones", "binoculars.fill", level: 2, of: 5, 0.41, "4,128 of 10,000", target: "10,000", ago: 60),
            badge("logkeeper", "Log Keeper", "milestones", "book.closed.fill", level: 3, of: 5, 0.52, "191 of 365", ago: 30),
            badge("streak", "On a Roll", "milestones", "flame.fill", level: 1, of: 4, 0.7, "21 of 30", ago: 90),
            badge("seasons", "Four Seasons", "milestones", "calendar", level: 2, of: 3, 0.58, "7 of 12", ago: 40),
            badge("places", "Home & Away", "milestones", "mappin.and.ellipse", level: 1, of: 3, 0.6, "9 of 15", ago: 70),
            badge("fence", "Fence Spotter", "milestones", "airplane.arrival", level: 1, of: 3, 0.4, "2 of 5", ago: 50),
            badge("farfromhome", "Far From Home", "milestones", "suitcase.fill", level: 1, of: 3, 0.33, "Farthest 820 mi", record: true, ago: 80),
            badge("fullhouse", "Full House", "milestones", "rectangle.on.rectangle", level: 1, of: 1, 1, "3 of 3", ago: 120),
            badge("queen", "Queen of the Skies", "rareBirds", "crown.fill", level: 2, of: 3, 0.3, "15 of 50", ago: 12),
            badge("superjumbo", "Superjumbo", "rareBirds", "airplane.circle.fill", level: 1, of: 3, 0.6, "3 of 5", ago: 20),
            badge("heavy", "Heavy Lifter", "rareBirds", "shippingbox.fill", level: 2, of: 3, 0.8, "4 of 5", ago: 9),
            badge("military", "Top Brass", "rareBirds", "shield.lefthalf.filled", level: 3, of: 4, 0.37, "93 of 250", ago: 3),
            badge("government", "Diplomatic", "rareBirds", "building.columns.fill", level: 1, of: 3, 0.5, "5 of 10", ago: 45),
            badge("medical", "Guardian Angel", "rareBirds", "cross.case.fill", level: 2, of: 4, 0.62, "31 of 50", ago: 15),
            badge("bomber", "Bomber", "rareBirds", "bolt.shield.fill", level: 0, of: 2, 0, "0 of 1"),
            badge("tiltrotor", "Tiltrotor", "rareBirds", "rotate.3d", level: 1, of: 2, 0.2, "2 of 10", ago: 100),
            badge("warbird", "Warbird", "rareBirds", "star.circle.fill", level: 0, of: 3, 0, "0 of 1"),
            badge("testflight", "Test Flight", "rareBirds", "testtube.2", level: 1, of: 1, 1, "1 of 1", ago: 33),
            badge("highflier", "High Flier", "rareBirds", "arrow.up.to.line", level: 1, of: 3, 0.33, "Highest 47,000 ft", record: true, ago: 25),
            badge("speed", "Speed Demon", "rareBirds", "gauge.with.dots.needle.100percent", level: 2, of: 3, 0.67, "Fastest 661 kts", record: true, ago: 18),
            badge("emergency", "Mayday", "moments", "exclamationmark.triangle.fill", level: 1, of: 3, 0.33, "1 of 3", ago: 140),
            badge("night", "Night Owl", "moments", "moon.stars.fill", level: 2, of: 4, 0.48, "24 of 50", ago: 22),
            badge("earlybird", "Early Bird", "moments", "sunrise.fill", level: 2, of: 4, 0.3, "15 of 50", ago: 28),
            badge("newyear", "Happy New Year", "moments", "party.popper.fill", level: 0, of: 1, 0, "0 of 1"),
            badge("boomerang", "Boomerang", "moments", "arrow.uturn.left.circle.fill", level: 1, of: 3, 0.7, "7 of 10", ago: 55),
            badge("roundclock", "Round the Clock", "moments", "clock.fill", level: 4, of: 4, 1, "48 of 48", ago: 2),
            badge("busy", "Busy Sky", "moments", "chart.bar.fill", level: 1, of: 3, 0.76, "38 of 50", ago: 65),
            badge("regular", "Regular", "moments", "arrow.triangle.2.circlepath", level: 2, of: 5, 0.88, "44 of 50", ago: 8),
            badge("clockwork", "Clockwork", "moments", "clock.arrow.circlepath", level: 1, of: 3, 0.4, "12 of 30", ago: 75),
            badge("overhead", "Right Overhead", "moments", "scope", level: 2, of: 4, 0.5, "Closest 0.2 mi", record: true, ago: 6),
            badge("airlines", "Globetrotter", "collections", "globe.americas.fill", level: 2, of: 5, 0.7, "42 of 60", ago: 35),
            badge("alphabet", "Alphabet", "collections", "textformat.abc", level: 2, of: 3, 0.85, "22 of 26", ago: 14),
            badge("types", "Type Collector", "collections", "square.stack.3d.up.fill", level: 2, of: 5, 0.87, "87 of 100", ago: 11),
            badge("rotor", "Rotorhead", "collections", "fan.fill", level: 2, of: 5, 0.21, "214 of 1,000", ago: 48),
            badge("countries", "Around the World", "collections", "flag.fill", level: 1, of: 4, 0.76, "19 of 25", ago: 26),
            badge("airports", "Departure Board", "collections", "signpost.right.fill", level: 1, of: 4, 0.6, "151 of 250", ago: 38),
            badge("continents", "Six Continents", "collections", "globe.asia.australia.fill", level: 2, of: 3, 0.83, "5 of 6", ago: 19),
            badge("silhouettes", "Silhouette Set", "collections", "square.grid.2x2.fill", level: 0, of: 1, 0.64, "16 of 25"),
            badge("longhaul", "Long Haul", "collections", "globe.europe.africa.fill", level: 2, of: 3, 0.67, "Longest 8,573 mi", record: true, ago: 41),
            badge("compass", "Compass Rose", "collections", "safari.fill", level: 1, of: 3, 0.75, "18 of 24", ago: 58),
            badge("shutterbug", "Shutterbug", "skyView", "camera.fill", level: 2, of: 5, 0.62, "31 of 50", ago: 4),
            badge("paparazzi", "Paparazzi", "skyView", "camera.aperture", level: 1, of: 3, 0.44, "11 of 25", ago: 17),
            badge("rareshot", "Rare Shot", "skyView", "star.square.on.square.fill", level: 1, of: 3, 0.3, "3 of 10", ago: 27),
            badge("closeup", "Close-up", "skyView", "plus.magnifyingglass", level: 0, of: 3, 0, "0 of 1"),
        ]
        return LogbookSnapshot(
            builtAt: Date(), total: 4_128, airframes: 3_377, types: 87, airlines: 42, countries: 19, notable: 214,
            helicopters: 214, photos: 31, recentDays: days, bestDay: DayCount(day: today.addingTimeInterval(-86_400 * 61), count: 112),
            bestStreak: 63, lastRun: 17, lastDay: today,
            today: Today(day: today, notable: 2, newTypes: ["Airbus A350-1000"], newAirlines: ["Qatar Airways"], closest: "0.4 mi · DL570"),
            records: [
                Record(id: "closest", title: "Closest pass", value: "0.2 mi", symbol: "scope", flight: "N911AE · Bell 407", date: Date()),
                Record(id: "highest", title: "Highest", value: "47,000 ft", symbol: "arrow.up.to.line", flight: "N650GD · Gulfstream G650", date: Date()),
                Record(id: "fastest", title: "Fastest", value: "661 kts", symbol: "gauge.with.dots.needle.100percent", flight: "UA902 · Boeing 777-200", date: Date()),
                Record(id: "route", title: "Longest route", value: "8,573 mi", symbol: "globe.americas", flight: "EK211 · Airbus A380-800", date: Date()),
            ],
            topAirlines: [Rank(name: "Delta Air Lines", count: 1_877), Rank(name: "Southwest Airlines", count: 412)],
            topTypes: [Rank(name: "Boeing 737-900", count: 512), Rank(name: "Airbus A321neo", count: 377)],
            badges: badges,
            nextUp: ["regular", "types", "alphabet", "heavy", "continents"],
            recent: ["roundclock", "military", "shutterbug", "overhead"],
            sky: Sky(place: "Atlanta, GA", count: 4_128,
                     hourly: [22, 9, 4, 3, 6, 31, 118, 251, 302, 288, 264, 247, 239, 251, 266, 281, 318, 334, 296, 241, 198, 151, 96, 51],
                     headings: [61, 44, 52, 120, 212, 98, 61, 40, 58, 49, 66, 141, 402, 177, 73, 58],
                     showsTimes: true, showsHeadings: true)
        )
    }
}
#endif
