import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: DashStore
    @FocusState private var isInputFocused: Bool

    @State private var exportDocument: BackupDocument?
    @State private var exportFilename = "DashProfit-Backup"
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingRestore: DashBackup?
    @State private var backupStatus: String?
    @State private var backupStatusIsError = false

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

                Section {
                    Button {
                        prepareExport()
                    } label: {
                        Label("Back Up to Files…", systemImage: "externaldrive.badge.icloud")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Restore from Backup…", systemImage: "arrow.counterclockwise.icloud")
                    }
                    if let backupStatus {
                        Text(backupStatus)
                            .font(.caption)
                            .foregroundStyle(backupStatusIsError ? .red : .green)
                    }
                } header: {
                    Text("Backup & Restore")
                } footer: {
                    Text("Saves all orders, mileage, shifts, expenses and settings as one file. Pick iCloud Drive to keep it safe if you lose your phone.")
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
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { result in
                switch result {
                case .success:
                    setStatus("Backup saved.", isError: false)
                case .failure(let error):
                    setStatus("Backup failed: \(error.localizedDescription)", isError: true)
                }
                exportDocument = nil
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json]
            ) { result in
                handleImport(result)
            }
            .confirmationDialog(
                "Replace All Data?",
                isPresented: Binding(
                    get: { pendingRestore != nil },
                    set: { if !$0 { pendingRestore = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingRestore
            ) { backup in
                Button("Replace with Backup", role: .destructive) {
                    store.restore(from: backup)
                    setStatus("Restored \(backup.summaryText).", isError: false)
                    pendingRestore = nil
                }
                Button("Cancel", role: .cancel) { pendingRestore = nil }
            } message: { backup in
                Text("Backup from \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)): \(backup.summaryText). Your current data and settings will be replaced (a safety copy is kept on this phone).")
            }
        }
    }

    private func prepareExport() {
        let backup = store.makeBackup()
        do {
            exportDocument = BackupDocument(data: try backup.encoded())
            exportFilename = backup.suggestedFilename
            showExporter = true
        } catch {
            setStatus("Backup failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pendingRestore = try DashBackup.decode(from: data)
        } catch {
            setStatus("Couldn't read that backup: \(error.localizedDescription)", isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        backupStatus = message
        backupStatusIsError = isError
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
