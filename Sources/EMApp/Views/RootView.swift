import SwiftUI
import EMCore
import EMSettings

/// Root view with NavigationStack routing per [A-058].
/// Error banners and modal alerts are attached here so they cover all navigation destinations.
public struct RootView: View {
    @State private var router = AppRouter()
    @Environment(ErrorPresenter.self) private var errorPresenter

    public init() {}

    public var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .home:
                        HomeView()
                    case .editor:
                        EditorShellView()
                    }
                }
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
            case .subscriptionOffer:
                // Subscription screen — implemented with FEAT-062
                Text("Pro AI")
                    .presentationDetents([.medium])
            }
        }
        .overlay(alignment: .top) {
            if let banner = errorPresenter.currentBanner {
                ErrorBannerView(error: banner) {
                    errorPresenter.dismissBanner()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: errorPresenter.currentBanner?.id)
        .errorAlert()
        .environment(router)
    }
}
