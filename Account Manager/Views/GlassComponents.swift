//
//  GlassComponents.swift
//  Account Manager
//
//  Shared liquid-glass UI primitives. Kept in sync with Library Helper.
//

import SwiftUI

// MARK: - Brand color

extension Color {
    static let ihmsBrand = Color(hex: "#003076")
}

// MARK: - GlassActionButton

struct GlassActionButton: View {
    let title: String
    let baseColor: Color
    let foreground: Color
    let font: Font
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let disabled: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed  = false

    var body: some View {
        Button { action() } label: {
            Text(title)
                .font(font)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    ZStack {
                        baseColor.opacity(disabled ? 0.5 : 0.95)

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(isHovering ? 0.08 : 0.12))
                            .blendMode(.overlay)

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(isHovering ? 0.25 : 0.30), lineWidth: 0.5)

                        if isHovering {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color.white.opacity(0.14), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .transition(.opacity)
                        }

                        if isPressed {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color.black.opacity(0.20))
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovering = h } }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { withAnimation(.easeInOut(duration: 0.15)) { isPressed = true  } } }
                .onEnded   { _ in               withAnimation(.easeInOut(duration: 0.15)) { isPressed = false } }
        )
    }
}

// MARK: - GlassToggleRow

struct GlassToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var subtitle: String? = nil
    var warningStyle: Bool = false
    /// When provided, used as the toggle tint and title colour when `isOn == true`
    var activeTint: Color? = nil

    @State private var isHovering = false

    private var effectiveTint: Color {
        // Always use activeTint when provided — if we only apply it when isOn=true, the toggle
        // animates from blue→amber mid-stroke causing a visible flash. The tint only affects
        // the track colour when ON, so using it unconditionally has no visible effect when OFF.
        if let t = activeTint { return t }
        return warningStyle ? .orange : Color.ihmsBrand
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    // Keep the title readable in both light and dark mode — only the
                    // toggle track is tinted, never the label text (a navy label is
                    // unreadable on a dark background).
                    .foregroundStyle(warningStyle ? Color.orange : Color.primary.opacity(0.9))
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(effectiveTint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.10 : 0.0))
                    .blendMode(.overlay)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    warningStyle
                        ? Color.orange.opacity(isHovering ? 0.6 : 0.4)
                        : Color.white.opacity(isHovering ? 0.30 : 0.25),
                    lineWidth: 0.5
                )
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        )
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovering = h } }
    }
}

// MARK: - GlassFullWidthButton

struct GlassFullWidthButton: View {
    let title:       String
    let systemImage: String
    let baseColor:   Color
    let disabled:    Bool
    let action:      () -> Void

    @State private var isHovering = false
    @State private var isPressed  = false

    var body: some View {
        Button { action() } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    baseColor.opacity(disabled ? 0.45 : 0.95)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.08 : 0.12))
                        .blendMode(.overlay)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(isHovering ? 0.30 : 0.25), lineWidth: 0.5)
                    if isHovering {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.14), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .transition(.opacity)
                    }
                    if isPressed {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.20))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: baseColor.opacity(isHovering && !disabled ? 0.35 : 0.15),
                    radius: isHovering ? 8 : 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovering = h } }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { withAnimation(.easeInOut(duration: 0.12)) { isPressed = true  } } }
                .onEnded   { _ in               withAnimation(.easeInOut(duration: 0.12)) { isPressed = false } }
        )
    }
}

// MARK: - SidebarToolButton

struct SidebarToolButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var badge: Int? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20, alignment: .center)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 0)

                if let count = badge {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.80) : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected
                                      ? Color.white.opacity(0.18)
                                      : Color.primary.opacity(0.08))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    if isSelected {
                        Color.ihmsBrand.opacity(0.95)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(isHovering ? 0.08 : 0.12))
                            .blendMode(.overlay)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(isHovering ? 0.25 : 0.30), lineWidth: 0.5)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(isHovering ? 0.10 : 0.0))
                            .blendMode(.overlay)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(isHovering ? 0.30 : 0.25), lineWidth: 0.5)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.85))
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovering = h } }
    }
}

// MARK: - WatchingIndicator

struct WatchingIndicator: View {
    let text: String
    var color: Color = .red
    @State private var pulse = false

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.75))
            .animation(.easeInOut(duration: 0.2), value: text)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08)).blendMode(.overlay)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(color, lineWidth: 1.5)
                    .blur(radius: pulse ? 4 : 2)
                    .opacity(pulse ? 0.35 : 0.85)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            )
            .onAppear { pulse = true }
    }
}

// MARK: - Horizontal swipe detector (trackpad two-finger swipe + scroll wheel)
//
// SwiftUI DragGesture only fires on click-drag; trackpad two-finger swipes
// and mouse horizontal scrolling generate NSEvent.scrollWheel events that
// DragGesture never sees. This modifier installs a scoped local event monitor.
//
// Behaviour:
//   Trackpad (hasPreciseScrollingDeltas = true):
//     • onDelta fires on every event — caller clamps to reveal range for smooth tracking.
//     • onSettle fires on phase .ended — caller decides snap direction from current offset.
//   Mouse wheel (hasPreciseScrollingDeltas = false):
//     • Direction is inverted relative to trackpad on macOS; we negate it automatically.
//     • Threshold accumulates; on crossing, onDelta(-∞) + onSettle() snap-reveal, or
//       onDelta(+∞) + onSettle() snap-hide.
// Vertical scrolls are always returned un-consumed so the sidebar still scrolls.

private final class HSwipeCoordinator: @unchecked Sendable {
    var monitor: Any?
    var isHovered         = false
    var mouseAccumulator: CGFloat = 0
    let mouseThreshold:   CGFloat = 28
    // When true, flips the mouse-scroll reveal direction (for mice whose drivers
    // report opposite direction to what macOS expects — e.g. Logitech MX Master).
    var invertMouseDirection = false

    var onDelta:  ((CGFloat) -> Void)?
    var onSettle: (() -> Void)?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isHovered else { return event }
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard abs(dx) > abs(dy) else { return event }

            // Trackpad gestures have a non-empty phase (.began/.changed/.ended).
            // Mouse scroll events (including Logitech precision wheels) have phase == [].
            let isTrackpadGesture = !event.phase.isEmpty

            if isTrackpadGesture {
                // Trackpad: smooth per-event delta. Left swipe → negative dx → reveal.
                DispatchQueue.main.async { self.onDelta?(dx) }
                if event.phase == .ended || event.phase == .cancelled {
                    DispatchQueue.main.async { self.onSettle?() }
                }
            } else {
                // Mouse scroll wheel. macOS convention: left scroll = negative dx.
                // To reveal right-side buttons, the user scrolls left → negative dx.
                // We negate so negative dx produces positive accumulation → reveal.
                // The invert toggle flips for mice whose drivers report the opposite sign.
                let effective = self.invertMouseDirection ? dx : -dx
                self.mouseAccumulator += effective
                if self.mouseAccumulator > self.mouseThreshold {
                    self.mouseAccumulator = 0
                    DispatchQueue.main.async { self.onDelta?(-9999); self.onSettle?() }
                } else if self.mouseAccumulator < -self.mouseThreshold / 2 {
                    self.mouseAccumulator = 0
                    DispatchQueue.main.async { self.onDelta?(9999); self.onSettle?() }
                }
            }
            return event   // never consume — vertical scrolls pass through
        }
    }

    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        mouseAccumulator = 0
    }
}

struct HSwipeDetector: ViewModifier {
    let invertMouseDirection: Bool
    let onDelta:  (CGFloat) -> Void
    let onSettle: () -> Void

    @State private var coordinator = HSwipeCoordinator()

    func body(content: Content) -> some View {
        content
            .onAppear { coordinator.install() }
            .onDisappear { coordinator.remove() }
            // Propagate setting changes immediately, even while not hovering
            .onChange(of: invertMouseDirection) { _, new in
                coordinator.invertMouseDirection = new
            }
            .onHover { hovering in
                if hovering {
                    coordinator.invertMouseDirection = invertMouseDirection
                    coordinator.onDelta  = onDelta
                    coordinator.onSettle = onSettle
                }
                coordinator.isHovered = hovering
                if !hovering { coordinator.mouseAccumulator = 0 }
            }
    }
}

extension View {
    func detectHorizontalSwipe(invertMouseDirection: Bool = false,
                               onDelta:  @escaping (CGFloat) -> Void,
                               onSettle: @escaping () -> Void) -> some View {
        modifier(HSwipeDetector(invertMouseDirection: invertMouseDirection,
                                onDelta: onDelta, onSettle: onSettle))
    }
}

// MARK: - AppearancePicker

struct AppearancePicker: View {
    @Binding var selection: String

    private let options: [(label: String, value: String)] = [
        ("Light", "light"),
        ("Dark",  "dark"),
        ("Auto",  "auto"),
    ]

    private let segW: CGFloat = 72
    private let segH: CGFloat = 30
    private let inset: CGFloat = 3

    private var selectedIndex: Int {
        options.firstIndex(where: { $0.value == selection }) ?? 0
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.22)).blendMode(.overlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.50), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                .frame(width: segW - inset * 2, height: segH - inset * 2)
                .offset(x: CGFloat(selectedIndex) * segW + inset, y: 0)
                .animation(.spring(response: 0.30, dampingFraction: 0.68), value: selectedIndex)

            HStack(spacing: 0) {
                ForEach(options, id: \.value) { option in
                    Text(option.label)
                        .font(.system(size: 12,
                                      weight: selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? .primary : .secondary)
                        .animation(.easeInOut(duration: 0.18), value: selection)
                        .frame(width: segW, height: segH)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.68)) {
                                selection = option.value
                            }
                        }
                }
            }
        }
        .frame(width: segW * CGFloat(options.count), height: segH)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        )
    }
}
