import SwiftUI
import EMCore

/// View modifier that presents data-loss-risk errors as modal alerts per [A-035].
/// Modal alerts require explicit user action — they do not auto-dismiss.
struct ErrorAlertModifier: ViewModifier {
    @Environment(ErrorPresenter.self) private var errorPresenter

    func body(content: Content) -> some View {
        @Bindable var presenter = errorPresenter
        content
            .alert(
                "Attention",
                isPresented: Binding(
                    get: { presenter.currentModal != nil },
                    set: { if !$0 { presenter.dismissModal() } }
                ),
                presenting: presenter.currentModal
            ) { error in
                ForEach(Array(error.recoveryActions.enumerated()), id: \.offset) { _, action in
                    Button(action.label) {
                        Task {
                            await action.perform()
                        }
                    }
                }
                Button("Dismiss", role: .cancel) {
                    errorPresenter.dismissModal()
                }
            } message: { error in
                Text(error.message)
            }
    }
}

extension View {
    /// Attaches the error alert modifier for data-loss-risk error presentation.
    func errorAlert() -> some View {
        modifier(ErrorAlertModifier())
    }
}
