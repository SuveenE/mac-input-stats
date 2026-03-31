import ApplicationServices
import IOKit.hid
import SwiftUI

@MainActor
final class PermissionChecker: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false
    private var timer: Timer?

    func startChecking() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.check()
            }
        }
    }

    func stopChecking() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let ax = AXIsProcessTrusted()
        let input = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted

        if ax != accessibilityGranted { accessibilityGranted = ax }
        if input != inputMonitoringGranted { inputMonitoringGranted = input }
    }
}

struct OnboardingView: View {
    @StateObject private var checker = PermissionChecker()

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                Text("Welcome to Input Stats")
                    .font(.title2.bold())
                Text("Grant two permissions so the app can track your activity across all apps.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            .padding(.horizontal, 24)

            Divider().padding(.horizontal, 16)

            // Steps
            VStack(spacing: 16) {
                permissionRow(
                    step: 1,
                    title: "Accessibility",
                    description: "Track clicks and scrolls",
                    granted: checker.accessibilityGranted,
                    action: requestAccessibility
                )

                permissionRow(
                    step: 2,
                    title: "Input Monitoring",
                    description: "Track keystrokes",
                    granted: checker.inputMonitoringGranted,
                    action: requestInputMonitoring
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            Divider().padding(.horizontal, 16)

            // Footer
            HStack {
                if !allGranted {
                    Text("Waiting for permissions…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The app will relaunch to apply permissions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Get Started") {
                    checker.stopChecking()
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allGranted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 400)
        .onAppear { checker.startChecking() }
        .onDisappear { checker.stopChecking() }
    }

    private var allGranted: Bool {
        checker.accessibilityGranted && checker.inputMonitoringGranted
    }

    private func permissionRow(step: Int, title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(granted ? .green : .blue)
                    .frame(width: 28, height: 28)
                if granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Text("Granted")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func requestInputMonitoring() {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
