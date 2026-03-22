import SwiftUI

// MARK: - Color Extension

extension Color {
    /// Initialize a Color from a hex string (e.g. "1a1a2e" or "#1a1a2e").
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    static let nirvanaIndigo = Color(hex: "1a1a2e")
    static let nirvanaGold = Color(hex: "c9a84c")
    static let nirvanaGlow = Color(hex: "e8b84b").opacity(0.2)
    static let nirvanaText = Color(hex: "e8e8e8")
    static let nirvanaPink = Color(hex: "d4727a")
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case gestures = "Gestures"
    case navigation = "Navigation"
    case menubar = "Menubar"
    case sound = "Sound"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .grid:       return "square.grid.3x3"
        case .gestures:   return "hand.draw"
        case .navigation: return "arrow.up.arrow.down"
        case .menubar:    return "menubar.rectangle"
        case .sound:      return "speaker.wave.2"
        }
    }
}

// MARK: - ConfigView

struct ConfigView: View {
    @State private var selectedTab: SettingsTab = .grid

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar

            // Content
            content
        }
        .frame(width: 600, height: 400)
        .background(Color.nirvanaIndigo)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nirvana")
                .font(.headline)
                .foregroundColor(.nirvanaGold)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ForEach(SettingsTab.allCases) { tab in
                sidebarItem(tab)
            }

            Spacer()

            Text("v0.1.0")
                .font(.caption2)
                .foregroundColor(Color.nirvanaText.opacity(0.4))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: 160)
        .background(Color.nirvanaIndigo.opacity(0.95))
    }

    private func sidebarItem(_ tab: SettingsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .frame(width: 20)
                    .foregroundColor(selectedTab == tab ? .nirvanaGold : Color.nirvanaText.opacity(0.6))
                Text(tab.rawValue)
                    .foregroundColor(selectedTab == tab ? .nirvanaGold : Color.nirvanaText.opacity(0.8))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                selectedTab == tab
                    ? RoundedRectangle(cornerRadius: 6)
                        .fill(Color.nirvanaGold.opacity(0.12))
                    : nil
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ZStack {
            // Frosted glass background
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)

            Group {
                switch selectedTab {
                case .grid:       GridTabView()
                case .gestures:   GesturesTabView()
                case .navigation: NavigationTabView()
                case .menubar:    MenubarTabView()
                case .sound:      SoundTabView()
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Grid Tab

private struct GridTabView: View {
    // Local state; in production this would bind to GridModel
    @State private var cells: [[Bool]] = [
        [true, true, true],
        [true, true, false],
        [false, false, false],
    ]
    @State private var currentRow = 0
    @State private var currentCol = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grid Layout")
                .font(.title3.bold())
                .foregroundColor(.nirvanaText)

            Text("Click cells to enable or disable Spaces. Enabled cells are mapped to macOS Spaces in row-major order.")
                .font(.caption)
                .foregroundColor(Color.nirvanaText.opacity(0.6))

            // 3x3 grid
            VStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { col in
                            gridCell(row: row, col: col)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .nirvanaGold, label: "Current")
                legendItem(color: Color.nirvanaText.opacity(0.3), label: "Enabled")
                legendItem(color: Color.nirvanaIndigo, label: "Disabled")
            }
            .font(.caption2)
            .foregroundColor(Color.nirvanaText.opacity(0.5))

            Spacer()
        }
    }

    private func gridCell(row: Int, col: Int) -> some View {
        let isCurrent = row == currentRow && col == currentCol
        let isEnabled = cells[row][col]
        let spaceIndex = spaceNumber(row: row, col: col)

        return Button(action: {
            // Don't allow disabling the current cell
            guard !(row == currentRow && col == currentCol) else { return }
            cells[row][col].toggle()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isCurrent
                            ? Color.nirvanaGold.opacity(0.3)
                            : isEnabled
                                ? Color.nirvanaText.opacity(0.08)
                                : Color.nirvanaIndigo.opacity(0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isCurrent ? Color.nirvanaGold : Color.nirvanaText.opacity(0.15),
                                lineWidth: isCurrent ? 2 : 1
                            )
                    )

                if isEnabled {
                    Text(spaceIndex != nil ? "\(spaceIndex!)" : "")
                        .font(.title2.monospacedDigit())
                        .foregroundColor(isCurrent ? .nirvanaGold : Color.nirvanaText.opacity(0.5))
                }
            }
            .frame(width: 72, height: 56)
        }
        .buttonStyle(.plain)
    }

    /// Returns the 1-based Space index for an enabled cell, or nil if disabled.
    private func spaceNumber(row: Int, col: Int) -> Int? {
        guard cells[row][col] else { return nil }
        var index = 1
        for r in 0..<3 {
            for c in 0..<3 {
                if r == row && c == col { return index }
                if cells[r][c] { index += 1 }
            }
        }
        return nil
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
        }
    }
}

// MARK: - Gestures Tab

private struct GesturesTabView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gestures")
                .font(.title3.bold())
                .foregroundColor(.nirvanaText)

            Text("Current gesture bindings. Customization coming in a future release.")
                .font(.caption)
                .foregroundColor(Color.nirvanaText.opacity(0.6))

            VStack(spacing: 12) {
                gestureRow(label: "Overlay Trigger", binding: "Option (hold)")
                gestureRow(label: "Horizontal Nav", binding: "3-finger swipe L/R")
                gestureRow(label: "Vertical Nav", binding: "3-finger swipe U/D")
                gestureRow(label: "Grid Navigate", binding: "Arrow keys (while overlay)")
                gestureRow(label: "Confirm Space", binding: "Release Option")
            }

            Spacer()
        }
    }

    private func gestureRow(label: String, binding: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.nirvanaText)
            Spacer()
            Text(binding)
                .font(.callout.monospaced())
                .foregroundColor(Color.nirvanaGold.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.nirvanaGold.opacity(0.1))
                )
        }
    }
}

// MARK: - Navigation Tab

private struct NavigationTabView: View {
    @State private var edgeWrap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Navigation")
                .font(.title3.bold())
                .foregroundColor(.nirvanaText)

            Text("Configure how grid navigation behaves at edges.")
                .font(.caption)
                .foregroundColor(Color.nirvanaText.opacity(0.6))

            Toggle(isOn: $edgeWrap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edge Wrap")
                        .foregroundColor(.nirvanaText)
                    Text("When enabled, navigating past an edge wraps to the opposite side. Default: off (spatial model stays solid).")
                        .font(.caption)
                        .foregroundColor(Color.nirvanaText.opacity(0.5))
                }
            }
            .toggleStyle(.switch)
            .tint(.nirvanaGold)

            Spacer()
        }
    }
}

// MARK: - Menubar Tab

private struct MenubarTabView: View {
    @State private var showInMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menu Bar")
                .font(.title3.bold())
                .foregroundColor(.nirvanaText)

            Text("The menu bar icon shows a tiny 3x3 grid with a dot indicating your current position.")
                .font(.caption)
                .foregroundColor(Color.nirvanaText.opacity(0.6))

            Toggle(isOn: $showInMenuBar) {
                Text("Show in Menu Bar")
                    .foregroundColor(.nirvanaText)
            }
            .toggleStyle(.switch)
            .tint(.nirvanaGold)

            Spacer()
        }
    }
}

// MARK: - Sound Tab

private struct SoundTabView: View {
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "speaker.slash")
                    .font(.system(size: 32))
                    .foregroundColor(Color.nirvanaText.opacity(0.3))
                Text("Sound")
                    .font(.title3.bold())
                    .foregroundColor(.nirvanaText)
                Text("Coming soon")
                    .font(.callout)
                    .foregroundColor(Color.nirvanaText.opacity(0.5))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

