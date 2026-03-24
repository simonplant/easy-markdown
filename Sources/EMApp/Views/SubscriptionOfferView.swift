import SwiftUI
import EMCloud
import EMCore

/// Pro AI subscription offer sheet per FEAT-062, [D-STORE-1], [D-BIZ-5], [D-BIZ-7].
/// Honest, clear, never pushy — sells Pro AI on its merits, not through dark patterns.
/// Satisfies Apple App Store Review Guideline 3.1.2.
struct SubscriptionOfferView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: SubscriptionPlan = .annual
    @State private var purchaseError: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    whatIsIncludedSection
                    pricingSection
                    cancellationSection
                    purchaseButton
                    restoreButton
                    legalSection
                }
                .padding()
            }
            .navigationTitle("Pro AI")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Purchase Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let purchaseError {
                    Text(purchaseError)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Cloud-powered AI for translation, tone adjustment, and more.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - What's Included

    private var whatIsIncludedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's included")
                .font(.headline)

            featureRow(icon: "globe", text: "Advanced translation across 20+ languages")
            featureRow(icon: "paintbrush", text: "Tone and style adjustment")
            featureRow(icon: "doc.text.magnifyingglass", text: "Document-level analysis")
            featureRow(icon: "text.cursor", text: "Generation from prompts")
            featureRow(icon: "brain", text: "State-of-the-art cloud models")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: 12) {
            Text("Choose a plan")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            planCard(
                plan: .annual,
                title: "Annual",
                priceLabel: annualPriceLabel,
                detail: annualDetailLabel,
                badge: "Save ~37%"
            )

            planCard(
                plan: .monthly,
                title: "Monthly",
                priceLabel: monthlyPriceLabel,
                detail: nil,
                badge: nil
            )
        }
    }

    private func planCard(
        plan: SubscriptionPlan,
        title: String,
        priceLabel: String,
        detail: String?,
        badge: String?
    ) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body.weight(.medium))
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.15))
                                .foregroundStyle(.tint)
                                .clipShape(Capsule())
                        }
                    }
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(priceLabel)
                    .font(.body.weight(.medium))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(title) plan, \(priceLabel)")
    }

    // MARK: - Price Labels

    /// Uses StoreKit product `displayPrice` when available, falls back to hardcoded values.
    private var monthlyPriceLabel: String {
        if let product = subscriptionManager.monthlyProduct {
            return "\(product.displayPrice)/month"
        }
        return "$3.99/month"
    }

    private var annualPriceLabel: String {
        if let product = subscriptionManager.annualProduct {
            return "\(product.displayPrice)/year"
        }
        return "$29.99/year"
    }

    private var annualDetailLabel: String? {
        if let annual = subscriptionManager.annualProduct {
            // Calculate equivalent monthly cost from annual price
            let monthlyEquivalent = annual.price / 12
            let formatted = monthlyEquivalent.formatted(annual.priceFormatStyle)
            return "Just \(formatted)/month"
        }
        return "Just $2.50/month"
    }

    // MARK: - Cancellation

    private var cancellationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("If you cancel")
                .font(.headline)
            Text("Your app and all local AI features keep working perfectly. You only lose access to cloud-powered Pro AI features. Cancel anytime from your device's Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Purchase

    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            Group {
                if subscriptionManager.isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else if subscriptionManager.isProActive {
                    Label("Subscribed", systemImage: "checkmark.circle.fill")
                } else {
                    Text("Subscribe")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(subscriptionManager.isPurchasing || subscriptionManager.isProActive)
        .accessibilityLabel(subscriptionManager.isProActive ? "Already subscribed" : "Subscribe to Pro AI")
    }

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task { await restore() }
        }
        .font(.footnote)
        .disabled(subscriptionManager.isPurchasing)
    }

    // MARK: - Legal

    private var legalSection: some View {
        VStack(spacing: 4) {
            Text("Payment is charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Your account is charged for renewal within 24 hours prior to the end of the current period.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Service",
                     destination: URL(string: "https://easymarkdown.com/terms")!)
                Link("Privacy Policy",
                     destination: URL(string: "https://easymarkdown.com/privacy")!)
            }
            .font(.caption2)
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func purchase() async {
        do {
            try await subscriptionManager.purchaseSubscription(plan: selectedPlan)
            // After successful purchase, dismiss — Pro AI actions work immediately
            // because SubscriptionManager.isProActive updates via @Observable.
            dismiss()
        } catch let error as EMError {
            switch error {
            case .purchase(.userCancelled):
                // User cancelled — no error to show
                break
            case .purchase(.purchasePending):
                // Pending parental approval etc. — dismiss quietly
                dismiss()
            default:
                purchaseError = error.localizedDescription
                showingError = true
            }
        } catch {
            purchaseError = error.localizedDescription
            showingError = true
        }
    }

    private func restore() async {
        do {
            try await subscriptionManager.restoreSubscriptions()
            if subscriptionManager.isProActive {
                dismiss()
            }
        } catch {
            purchaseError = "Could not restore purchases. Please try again."
            showingError = true
        }
    }
}
