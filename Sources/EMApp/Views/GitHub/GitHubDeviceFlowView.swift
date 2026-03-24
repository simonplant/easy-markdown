import SwiftUI
import EMGit
import EMCore

/// Shows the GitHub OAuth device flow UI per [A-064] AC1.
/// Displays the user code and a button to open github.com/login/device.
/// No web view embedded in the app — user opens their browser.
/// Used inline within RepoBrowserView when not authenticated.
struct GitHubDeviceFlowView: View {
    @Environment(GitHubOAuthManager.self) private var oauthManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Sign in to GitHub")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if let info = oauthManager.deviceFlowInfo {
                deviceCodeSection(info: info)
            } else if oauthManager.isAuthenticating {
                ProgressView("Connecting to GitHub\u{2026}")
                    .accessibilityLabel("Connecting to GitHub")
            } else if case .failed(let error) = oauthManager.authState {
                errorSection(error: error)
            } else {
                startSection
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Device Code Display

    private func deviceCodeSection(info: GitHubDeviceCodeResponse) -> some View {
        VStack(spacing: 20) {
            Text("Enter this code at GitHub:")
                .font(.body)
                .foregroundStyle(.secondary)

            Text(info.userCode)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel("Device code: \(info.userCode)")

            Button {
                openURL(info.verificationURI)
            } label: {
                Label("Open GitHub", systemImage: "safari")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Opens github.com in your browser to enter the code")
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif

            Text("Waiting for authorization\u{2026}")
                .font(.caption)
                .foregroundStyle(.tertiary)

            ProgressView()
                .accessibilityLabel("Waiting for authorization")
        }
    }

    // MARK: - Start

    private var startSection: some View {
        VStack(spacing: 16) {
            Text("Sign in once to browse your repositories.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await oauthManager.startDeviceFlow()
                }
            } label: {
                Label("Sign in with GitHub", systemImage: "person.badge.key")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Starts the GitHub sign-in process")
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif
        }
    }

    // MARK: - Error

    private func errorSection(error: EMError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(error.errorDescription ?? "Authentication failed.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await oauthManager.startDeviceFlow()
                }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Retries the GitHub sign-in process")
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif
        }
    }
}
