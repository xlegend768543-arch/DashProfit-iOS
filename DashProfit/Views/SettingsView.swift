import SwiftUI

struct SettingsView: View {
    @Bindable var store: DashStore
    @FocusState private var isInputFocused: Bool

    private var taxSetAsidePercentBinding: Binding<Double> {
        Binding(
            get: { store.settings.incomeTaxSetAsidePct * 100.0 },
            set: { newValue in
                let clamped = min(max(newValue.isFinite ? newValue : 0, 0), 50)
                store.settings.incomeTaxSetAsidePct = clamped / 100.0
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    doubleRow("Target Net $/Hr ($)", value: $store.settings.minNetHourly)
                    doubleRow("Min Eff. $/Mile ($)", value: $store.settings.minPerMile)
                    doubleRow("Min Order Payout ($)", value: $store.settings.minPayout)
                    doubleRow("Daily Net Goal ($)", value: $store.settings.dailyGoal)
                } header: {
                    Text("Decision Rules (Take vs. Pass)")
                } footer: {
                    Text("Offers meeting both Net $/Hr and Eff. $/Mi minimums score as STRONG TAKE. Set Daily Net Goal to 0 to hide the goal bar.")
                }

                Section {
                    doubleRow("Vehicle MPG", value: $store.settings.mpg)
                    doubleRow("Gas Price ($/gal)", value: $store.settings.gasPrice)
                    doubleRow("Wear & Maint. ($/mi)", value: $store.settings.wearPerMile)
                    doubleRow("IRS Deduction ($/mi)", value: $store.settings.irsRate)
                    doubleRow("Income Tax Set-Aside (%)", value: taxSetAsidePercentBinding)
                } header: {
                    Text("Vehicle & Expense Model")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "Estimated vehicle cost: $%.2f/mi", store.settings.costPerMile))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("Verify current standard mileage rate at irs.gov. Tax Write-Off and Set-Aside are planning estimates only — consult a tax professional.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Rules & Car")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                        store.settings = store.settings.sanitized
                    }
                }
            }
            .onChange(of: isInputFocused) { _, focused in
                if !focused {
                    store.settings = store.settings.sanitized
                }
            }
            .onDisappear {
                store.settings = store.settings.sanitized
            }
        }
    }

    private func doubleRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .font(.body.weight(.semibold))
                .focused($isInputFocused)
        }
    }
}
