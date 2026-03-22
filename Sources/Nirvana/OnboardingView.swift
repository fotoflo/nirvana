import SwiftUI
import AppKit

// MARK: - Onboarding State

enum OnboardingStep: Int, CaseIterable {
    case createSpaces = 0
    case arrangeGrid = 1
    case grantPermissions = 2
}

// MARK: - OnboardingView

/// 3-step first-launch onboarding flow matching the design mockup.
/// Step 1: Create your Spaces
/// Step 2: Arrange your grid
/// Step 3: Grant permissions (Accessibility + Screen Recording)
struct OnboardingView: View {
    @ObservedObject var gridModel: GridModel
    @State private var currentStep: OnboardingStep = .createSpaces
    @State private var detectedSpaceCount: Int = 0
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            // Background matching Nirvana's visual identity
            Color.nirvanaIndigo
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Title
                Text("Get Started")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Color.nirvanaGold)
                    .padding(.top, 32)
                    .padding(.bottom, 24)

                // Step content
                Group {
                    switch currentStep {
                    case .createSpaces:
                        createSpacesStep
                    case .arrangeGrid:
                        arrangeGridStep
                    case .grantPermissions:
                        permissionsStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Step indicators
                HStack(spacing: 8) {
                    ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                        Circle()
                            .fill(step == currentStep ? Color.nirvanaGold : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .frame(width: 500, height: 520)
        .onAppear {
            checkPermissions()
        }
    }

    // MARK: - Step 1: Create Spaces

    private var createSpacesStep: some View {
        OnboardingCard(
            stepNumber: 1,
            title: "Create your Spaces",
            subtitle: "Set up areas for work, home, leisure, etc."
        ) {
            VStack(spacing: 16) {
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(icon: "rectangle.3.group", text: "Open Mission Control (swipe up with 4 fingers)")
                    instructionRow(icon: "plus.circle", text: "Click '+' in the top-right to add Spaces")
                    instructionRow(icon: "square.grid.3x3", text: "Create up to 9 Spaces for a full 3×3 grid")
                }
                .padding(.horizontal, 8)

                // Space count indicator
                HStack {
                    Text("Spaces detected:")
                        .foregroundColor(Color.nirvanaText.opacity(0.7))
                    Text("\(detectedSpaceCount) of 9")
                        .foregroundColor(Color.nirvanaGold)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 14))

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.nirvanaGold)
                            .frame(width: geo.size.width * CGFloat(min(detectedSpaceCount, 9)) / 9.0, height: 8)
                    }
                }
                .frame(height: 8)

                Button(action: refreshSpaceCount) {
                    Label("Refresh Count", systemImage: "arrow.clockwise")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color.nirvanaGold)
            }
        } continueAction: {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = .arrangeGrid
            }
        }
    }

    // MARK: - Step 2: Arrange Grid

    private var arrangeGridStep: some View {
        OnboardingCard(
            stepNumber: 2,
            title: "Arrange your grid",
            subtitle: "Toggle cells to match your Spaces layout."
        ) {
            VStack(spacing: 12) {
                // 3x3 grid of toggleable cells
                ForEach((0..<3).reversed(), id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { col in
                            let enabled = gridModel.config.isEnabled(row: row, col: col)
                            let spaceNum = row * 3 + col + 1

                            Button(action: {
                                gridModel.toggleCell(row: row, col: col)
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(enabled ? Color.white.opacity(0.15) : Color.white.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(
                                                    enabled ? Color.nirvanaGold.opacity(0.6) : Color.white.opacity(0.15),
                                                    style: enabled ? StrokeStyle(lineWidth: 1.5) : StrokeStyle(lineWidth: 1, dash: [4, 3])
                                                )
                                        )
                                    Text("\(spaceNum)")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(enabled ? Color.nirvanaText : Color.nirvanaText.opacity(0.3))
                                }
                                .frame(width: 80, height: 55)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("\(gridModel.enabledCells.count) spaces enabled")
                    .font(.system(size: 13))
                    .foregroundColor(Color.nirvanaText.opacity(0.6))
            }
        } continueAction: {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = .grantPermissions
            }
        }
    }

    // MARK: - Step 3: Permissions

    private var permissionsStep: some View {
        OnboardingCard(
            stepNumber: 3,
            title: "Grant permissions",
            subtitle: "This lets it manage your windows."
        ) {
            VStack(spacing: 16) {
                // App name
                HStack {
                    Image(systemName: "square.grid.3x3.fill")
                        .foregroundColor(Color.nirvanaGold)
                    Text("Nirvana")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.nirvanaText)
                    Spacer()
                }

                // Accessibility permission
                permissionRow(
                    name: "Accessibility",
                    granted: accessibilityGranted,
                    action: requestAccessibility
                )

                // Screen Recording permission
                permissionRow(
                    name: "Screen Recording",
                    granted: screenRecordingGranted,
                    action: requestScreenRecording
                )

                // Status
                if accessibilityGranted && screenRecordingGranted {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Permissions granted!")
                            .foregroundColor(Color.nirvanaText)
                    }
                    .font(.system(size: 14))
                } else {
                    Text("You can grant these later in System Settings.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.nirvanaText.opacity(0.5))
                }

                Button(action: checkPermissions) {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color.nirvanaGold)
            }
        } continueAction: {
            completeOnboarding()
        }
    }

    // MARK: - Helpers

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Color.nirvanaGold)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color.nirvanaText.opacity(0.9))
        }
    }

    private func permissionRow(name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Circle()
                .fill(granted ? Color.green : Color.white.opacity(0.3))
                .frame(width: 10, height: 10)
            Text(name)
                .font(.system(size: 14))
                .foregroundColor(Color.nirvanaText)
            Spacer()
            if !granted {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.nirvanaGold)
                .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }

    private func refreshSpaceCount() {
        let bridge = SpaceBridge(gridModel: gridModel)
        let spaces = bridge.listSpaceIDs()
        detectedSpaceCount = max(spaces.count, 1) // At least 1 space always exists
    }

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    private func requestAccessibility() {
        // Open System Settings to Accessibility pane
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Re-check after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            checkPermissions()
        }
    }

    private func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        // Re-check after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            checkPermissions()
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "nirvana.onboardingCompleted")
        onComplete()
    }
}

// MARK: - Onboarding Card

/// Reusable frosted glass card for each onboarding step.
struct OnboardingCard<Content: View>: View {
    let stepNumber: Int
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    let continueAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Step number badge
            Text("\(stepNumber)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.nirvanaGold)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.nirvanaGold.opacity(0.2)))

            // Title
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.nirvanaText)

            // Subtitle
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Color.nirvanaText.opacity(0.6))

            // Content
            content()

            Spacer()

            // Continue button
            Button(action: continueAction) {
                Text("Continue")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.nirvanaIndigo)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.nirvanaGold)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 32)
    }
}
