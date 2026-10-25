import SwiftUI
import UIKit

enum Theme {
    static let night = Color(red: 0.45, green: 0.38, blue: 0.98)
    static let day = Color(red: 1.0, green: 0.66, blue: 0.16)
    static let good = Color(red: 0.16, green: 0.72, blue: 0.45)
    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.18, green: 0.42, blue: 1.0), Color(red: 0.40, green: 0.26, blue: 0.92)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let nightGradient = LinearGradient(
        colors: [Color(red: 0.06, green: 0.07, blue: 0.20), Color(red: 0.16, green: 0.10, blue: 0.38)],
        startPoint: .top, endPoint: .bottom
    )
    static let dayGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.32, blue: 0.85), Color(red: 0.20, green: 0.55, blue: 0.95)],
        startPoint: .top, endPoint: .bottom
    )
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

/// A circular progress ring with a rounded cap and soft track.
struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.75), color], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(0.01, min(1, progress)))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: progress)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A selectable capsule used for weather, roads and skills.
struct ToggleChip: View {
    let label: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// Lays children out left-to-right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Multi-select chips for any CaseIterable option set.
struct ChipPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Set<Option>
    let label: (Option) -> String
    let symbol: (Option) -> String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                ToggleChip(label: label(option), symbol: symbol(option), isOn: selection.contains(option)) {
                    if selection.contains(option) { selection.remove(option) } else { selection.insert(option) }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }
    }
}

/// Day/night split bar.
struct DayNightBar: View {
    let dayMinutes: Double
    let nightMinutes: Double

    var body: some View {
        GeometryReader { geo in
            let total = max(1, dayMinutes + nightMinutes)
            HStack(spacing: 2) {
                if dayMinutes > 0 {
                    Capsule().fill(Theme.day).frame(width: max(4, geo.size.width * dayMinutes / total))
                }
                if nightMinutes > 0 {
                    Capsule().fill(Theme.night)
                }
            }
        }
        .frame(height: 8)
        .background(Capsule().fill(Color(.tertiarySystemFill)))
        .accessibilityElement()
        .accessibilityLabel("Day \(Fmt.duration(minutes: dayMinutes)), night \(Fmt.duration(minutes: nightMinutes))")
    }
}

struct Banner: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .orange
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var dismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Wraps UIActivityViewController so we know when (and where) something was shared.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: ((UIActivity.ActivityType?, Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { type, completed, _, _ in
            onComplete?(type, completed)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    static let notesActivity = UIActivity.ActivityType(rawValue: "com.apple.mobilenotes.SharingExtension")
}

/// Identifiable payload for `.sheet(item:)`.
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
    var isNotesBackup = false
}

extension View {
    /// Standard grouped background used across screens.
    func screenBackground() -> some View {
        background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
