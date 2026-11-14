import SwiftUI
import UIKit

struct EvaluateView: View {
    @Bindable var store: DashStore
    @Bindable var mileageTracker: MileageTrackerService

    @State private var payoutText = ""
    @State private var milesText = ""
    @State private var minutesText = ""
    @State private var merchantText = ""
    @State private var deadhead: DeadheadOption = .inZone
    @State private var waitRisk: WaitRiskOption = .fast
    @State private var orderType: OrderType = .food
    @State private var statusMessage: String?
    @State private var focusTrigger = 0
    @State private var logTrigger = 0

    private var evaluation: OfferEvaluation? {
        guard let payout = Double(payoutText),
              let miles = Double(milesText),
              let minutes = Int(minutesText) else {
            return nil
        }
        return OfferCalculator.evaluate(
            payout: payout,
            miles: miles,
            minutes: minutes,
            deadheadMultiplier: deadhead.rawValue,
            waitMinutes: waitRisk.rawValue,
            settings: store.settings
        )
    }

    var body: some View {
        let eval = evaluation

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    MileageBarView(
                        store: store,
                        mileageTracker: mileageTracker,
                        onUseTrip: { tripMiles in
                            milesText = String(format: "%.1f", tripMiles)
                            deadhead = .inZone
                            statusMessage = String(format: "Loaded %.1f GPS trip mi (In Zone)", tripMiles)
                        },
                        onStatusMessage: { msg in
                            statusMessage = msg
                        }
                    )

                    VerdictCardView(
                        evaluation: eval,
                        merchantName: merchantText,
                        history: OfferCalculator.merchantHistory(for: merchantText, in: store.orders)
                    )

                    InputCardView(
                        payoutText: $payoutText,
                        milesText: $milesText,
                        minutesText: $minutesText,
                        merchantText: $merchantText,
                        deadhead: $deadhead,
                        waitRisk: $waitRisk,
                        orderType: $orderType,
                        statusMessage: $statusMessage,
                        evaluation: eval,
                        focusTrigger: focusTrigger,
                        onLog: { decision in
                            log(decision, evaluation: eval)
                        }
                    )
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("DashProfit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") { resetForm() }
                        .font(.subheadline.weight(.semibold))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .sensoryFeedback(.selection, trigger: eval?.verdict) { oldValue, newValue in
                newValue != nil && oldValue != newValue
            }
            .sensoryFeedback(.success, trigger: logTrigger)
        }
    }

    private func log(_ decision: OrderDecision, evaluation: OfferEvaluation?) {
        guard let evaluation else { return }
        store.logOrder(
            evaluation: evaluation,
            decision: decision,
            merchant: merchantText,
            orderType: orderType,
            deadheadMultiplier: deadhead.rawValue,
            waitMinutes: waitRisk.rawValue
        )
        resetForm()
        statusMessage = decision == .take ? "Logged as Taken" : "Logged as Passed"
        logTrigger += 1
        focusTrigger += 1
    }

    private func resetForm() {
        payoutText = ""
        milesText = ""
        minutesText = ""
        merchantText = ""
        deadhead = .inZone
        waitRisk = .fast
        orderType = .food
        statusMessage = nil
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
