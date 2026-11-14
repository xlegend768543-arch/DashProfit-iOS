import SwiftUI
import UIKit

/// Fix a logged order's numbers or decision; everything is recalculated.
struct OrderEditView: View {
    @Bindable var store: DashStore
    let order: LoggedOrder

    @Environment(\.dismiss) private var dismiss

    @State private var payoutText: String
    @State private var milesText: String
    @State private var minutesText: String
    @State private var merchantText: String
    @State private var deadhead: DeadheadOption
    @State private var waitRisk: WaitRiskOption
    @State private var orderType: OrderType
    @State private var decision: OrderDecision

    init(store: DashStore, order: LoggedOrder) {
        self.store = store
        self.order = order
        _payoutText = State(initialValue: String(format: "%.2f", order.payout))
        _milesText = State(initialValue: String(format: "%.1f", order.shownMiles))
        _minutesText = State(initialValue: "\(order.estimatedMinutes)")
        _merchantText = State(initialValue: order.merchant == LoggedOrder.defaultMerchantName ? "" : order.merchant)
        _deadhead = State(initialValue: DeadheadOption(rawValue: order.deadheadMultiplier) ?? .inZone)
        _waitRisk = State(initialValue: WaitRiskOption(rawValue: order.waitMinutes) ?? .fast)
        _orderType = State(initialValue: order.orderType)
        _decision = State(initialValue: order.decision)
    }

    private var parsedInputs: (payout: Double, miles: Double, minutes: Int)? {
        guard let payout = Double(payoutText),
              let miles = Double(milesText),
              let minutes = Int(minutesText) else { return nil }
        return (payout, miles, minutes)
    }

    private var preview: OfferEvaluation? {
        guard let p = parsedInputs else { return nil }
        return OfferCalculator.evaluate(
            payout: p.payout,
            miles: p.miles,
            minutes: p.minutes,
            deadheadMultiplier: deadhead.rawValue,
            waitMinutes: waitRisk.rawValue,
            settings: store.settings
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Decision", selection: $decision) {
                        Text("Taken").tag(OrderDecision.take)
                        Text("Passed").tag(OrderDecision.pass)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Logged \(order.timestamp.formatted(date: .abbreviated, time: .shortened))")
                }

                Section("Offer") {
                    numberRow("Payout ($)", text: $payoutText, keyboard: .decimalPad)
                    numberRow("Miles", text: $milesText, keyboard: .decimalPad)
                    numberRow("Est. Minutes", text: $minutesText, keyboard: .numberPad)
                    TextField("Restaurant / Store", text: $merchantText)
                }

                Section("Details") {
                    Picker("Deadhead", selection: $deadhead) {
                        ForEach(DeadheadOption.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Wait Risk", selection: $waitRisk) {
                        ForEach(WaitRiskOption.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Order Type", selection: $orderType) {
                        ForEach(OrderType.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section {
                    if let preview {
                        LabeledContent("Net Profit", value: String(format: "$%.2f", preview.netProfit))
                        LabeledContent("Net $/Hr", value: String(format: "$%.2f", preview.netHourly))
                        LabeledContent("Eff. $/Mi", value: String(format: "$%.2f", preview.effectivePerMile))
                    } else {
                        Text("Enter a payout above $0, miles, and minutes above 0.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recalculated")
                } footer: {
                    Text("Uses your current car-cost settings from Rules & Car.")
                }
            }
            .navigationTitle("Edit Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(preview == nil)
                }
            }
        }
    }

    private func save() {
        guard let p = parsedInputs else { return }
        let saved = store.updateOrder(
            id: order.id,
            payout: p.payout,
            miles: p.miles,
            minutes: p.minutes,
            deadheadMultiplier: deadhead.rawValue,
            waitMinutes: waitRisk.rawValue,
            orderType: orderType,
            merchant: merchantText,
            decision: decision
        )
        if saved { dismiss() }
    }

    private func numberRow(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .font(.body.weight(.semibold))
        }
    }
}
