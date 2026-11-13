import SwiftUI
import PhotosUI

struct InputCardView: View {
    @Binding var payoutText: String
    @Binding var milesText: String
    @Binding var minutesText: String
    @Binding var merchantText: String
    @Binding var deadhead: DeadheadOption
    @Binding var waitRisk: WaitRiskOption
    @Binding var orderType: OrderType
    @Binding var statusMessage: String?

    let evaluation: OfferEvaluation?
    let focusTrigger: Int
    let onLog: (OrderDecision) -> Void

    @State private var voiceService = VoiceInputService()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isScanningScreenshot = false
    @State private var scanErrorMessage: String?

    @FocusState private var focusedField: Field?
    private enum Field { case payout, miles, minutes, merchant }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button {
                    focusedField = nil
                    voiceService.toggleListening { parsed in
                        applyParsedOffer(parsed)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: voiceService.isListening ? "waveform.circle.fill" : "mic.fill")
                            .font(.body)
                        Text(voiceService.isListening ? "Stop" : "Speak Offer")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                    .background(voiceService.isListening ? Color.red.opacity(0.2) : Color.green.opacity(0.16))
                    .foregroundStyle(voiceService.isListening ? .red : .green)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(voiceService.isListening ? Color.red.opacity(0.55) : Color.green.opacity(0.45), lineWidth: 1)
                    )
                }
                .accessibilityLabel(voiceService.isListening ? "Stop voice input" : "Speak offer details")

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 6) {
                        if isScanningScreenshot {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "text.viewfinder")
                                .font(.body)
                        }
                        Text(isScanningScreenshot ? "Scanning..." : "Scan Offer")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                }
                .disabled(isScanningScreenshot)
                .accessibilityLabel("Scan offer screenshot with Vision OCR")
            }

            if voiceService.isListening || !voiceService.transcript.isEmpty {
                Text(voiceService.transcript.isEmpty ? "Say payout, miles, and minutes (e.g. \"$13.50, 4.2 mi, 21 min\")..." : "\"\(voiceService.transcript)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let voiceError = voiceService.errorMessage {
                Text(voiceError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let scanErrorMessage {
                Text(scanErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Examples:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    exampleChip("Chipotle $13.50", payout: "13.50", miles: "4.2", mins: "21", deadhead: .inZone, wait: .fast, type: .food, merchant: "Chipotle")
                    exampleChip("Outback $12", payout: "12.00", miles: "5.0", mins: "22", deadhead: .edge, wait: .moderate, type: .food, merchant: "Outback")
                    exampleChip("Popeyes $4.50", payout: "4.50", miles: "6.1", mins: "24", deadhead: .roundTrip, wait: .moderate, type: .food, merchant: "Popeyes")
                    exampleChip("Target $19.25", payout: "19.25", miles: "4.8", mins: "32", deadhead: .inZone, wait: .fast, type: .shop, merchant: "Target")
                }
            }

            HStack(spacing: 8) {
                numberField(title: "Payout ($)", placeholder: "11.50", text: $payoutText, keyboard: .decimalPad, field: .payout)
                numberField(title: "Miles", placeholder: "4.2", text: $milesText, keyboard: .decimalPad, field: .miles)
                numberField(title: "Est. Min", placeholder: "22", text: $minutesText, keyboard: .numberPad, field: .minutes)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Time:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach([12, 18, 25, 35, 45], id: \.self) { mins in
                        Button("\(mins)m") {
                            minutesText = "\(mins)"
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Return / Zone Deadhead")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(deadhead.hint)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                Picker("Deadhead", selection: $deadhead) {
                    ForEach(DeadheadOption.allCases) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wait Risk")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Wait Risk", selection: $waitRisk) {
                        ForEach(WaitRiskOption.allCases) { opt in
                            Text(opt.label).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Order Type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Order Type", selection: $orderType) {
                        ForEach(OrderType.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Restaurant / Store (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g., Chipotle, Target, Chick-fil-A", text: $merchantText)
                    .focused($focusedField, equals: .merchant)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    focusedField = nil
                    onLog(.pass)
                } label: {
                    Text("Log Pass")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(evaluation == nil)

                Button {
                    focusedField = nil
                    onLog(.take)
                } label: {
                    Text("Log Taken")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .background(evaluation == nil ? Color.green.opacity(0.35) : Color.green)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(evaluation == nil)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            focusedField = .payout
        }
        .onChange(of: focusTrigger) { _, _ in
            focusedField = .payout
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            scanErrorMessage = nil
            isScanningScreenshot = true
            Task {
                defer {
                    isScanningScreenshot = false
                    selectedPhotoItem = nil
                }
                guard let data = try? await newItem.loadTransferable(type: Data.self) else {
                    scanErrorMessage = "Could not load selected screenshot."
                    return
                }
                guard let parsed = await VoiceInputService.recognizeOfferFromImageData(data),
                      parsed.payout != nil || parsed.miles != nil || parsed.minutes != nil else {
                    scanErrorMessage = "No payout, miles, or time found in screenshot."
                    return
                }
                applyParsedOffer(parsed)
                statusMessage = "Scanned offer from screenshot"
                focusedField = nil
            }
        }
    }

    private func applyParsedOffer(_ parsed: ParsedVoiceOffer) {
        if let payout = parsed.payout { payoutText = String(format: "%.2f", payout) }
        if let miles = parsed.miles { milesText = String(format: "%.1f", miles) }
        if let minutes = parsed.minutes { minutesText = "\(minutes)" }
        if let deadhead = parsed.deadhead { self.deadhead = deadhead }
        if let orderType = parsed.orderType { self.orderType = orderType }
    }

    private func numberField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .focused($focusedField, equals: field)
                .font(.headline.weight(.bold))
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func exampleChip(
        _ title: String,
        payout: String,
        miles: String,
        mins: String,
        deadhead: DeadheadOption,
        wait: WaitRiskOption,
        type: OrderType,
        merchant: String
    ) -> some View {
        Button(title) {
            payoutText = payout
            milesText = miles
            minutesText = mins
            self.deadhead = deadhead
            waitRisk = wait
            orderType = type
            merchantText = merchant
            statusMessage = "Loaded example: \(merchant)"
            scanErrorMessage = nil
            focusedField = nil
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.14))
        .foregroundStyle(.green)
        .clipShape(Capsule())
    }
}
