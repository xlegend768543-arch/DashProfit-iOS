import AVFoundation
import Foundation
import Observation
import Speech
import UIKit
import Vision

struct ParsedVoiceOffer {
    var payout: Double?
    var miles: Double?
    var minutes: Int?
    var deadhead: DeadheadOption?
    var orderType: OrderType?
}

@Observable
final class VoiceInputService {
    var isListening = false
    var transcript = ""
    var errorMessage: String?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func toggleListening(onUpdate: @escaping (ParsedVoiceOffer) -> Void) {
        if isListening {
            stopListening()
        } else {
            Task { @MainActor in
                await startListening(onUpdate: onUpdate)
            }
        }
    }

    @MainActor
    func startListening(onUpdate: @escaping (ParsedVoiceOffer) -> Void) async {
        errorMessage = nil

        let speechAuth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechAuth == .authorized else {
            errorMessage = "Speech recognition permission is required in Settings."
            return
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            errorMessage = "Microphone permission is required in Settings."
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer is currently unavailable."
            return
        }

        stopListening()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            transcript = ""

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in
                        self.transcript = text
                        onUpdate(Self.parseSpokenOffer(text))
                        if result.isFinal {
                            self.stopListening()
                        }
                    }
                } else if error != nil {
                    Task { @MainActor in
                        self.stopListening()
                    }
                }
            }
        } catch {
            errorMessage = "Could not start microphone: \(error.localizedDescription)"
            stopListening()
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static let milesRegex = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(?:miles?|mi\b)"#, options: [])
    private static let hrRegex = try! NSRegularExpression(pattern: #"(\d+)\s*(?:hours?|hrs?)\s*(?:and\s*)?(\d+)\s*(?:minutes?|mins?|m\b)"#, options: [])
    private static let minRegex = try! NSRegularExpression(pattern: #"(\d{1,3})\s*(?:minutes?|mins?|min\b)"#, options: [])
    private static let dollarRegex = try! NSRegularExpression(pattern: #"\$\s*(\d{1,3}(?:\.\d{1,2})?)"#, options: [])
    private static let dcRegex = try! NSRegularExpression(pattern: #"(\d{1,3})\s*dollars?(?:\s*(?:and\s*)?(\d{1,2})\s*cents?)?"#, options: [])
    private static let firstNumRegex = try! NSRegularExpression(pattern: #"\b(\d{1,3}(?:\.\d{1,2})?)\b"#, options: [])

    /// Parses spoken or OCR'd phrases like "$13.50, 4.2 miles, 21 minutes" or "12 dollars 5 miles 20 min round trip".
    static func parseSpokenOffer(_ rawText: String) -> ParsedVoiceOffer {
        let text = rawText.lowercased()
        var result = ParsedVoiceOffer()
        var remainder = text

        // 1. Miles: "4.2 miles", "4.2 mi", "5 mile"
        if let match = milesRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let fullRange = Range(match.range(at: 0), in: text),
           let numRange = Range(match.range(at: 1), in: text) {
            result.miles = Double(text[numRange])
            remainder = remainder.replacingOccurrences(of: String(text[fullRange]), with: " ")
        }

        // 2. Minutes: "1 hour 10 minutes", "21 minutes", "21 mins", "21 min"
        if let match = hrRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let fullRange = Range(match.range(at: 0), in: text),
           let r1 = Range(match.range(at: 1), in: text),
           let r2 = Range(match.range(at: 2), in: text),
           let hrs = Int(text[r1]), let mins = Int(text[r2]) {
            result.minutes = hrs * 60 + mins
            remainder = remainder.replacingOccurrences(of: String(text[fullRange]), with: " ")
        } else if let match = minRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let fullRange = Range(match.range(at: 0), in: text),
                  let numRange = Range(match.range(at: 1), in: text) {
            result.minutes = Int(text[numRange])
            remainder = remainder.replacingOccurrences(of: String(text[fullRange]), with: " ")
        }

        // 3. Payout: "$13.50", "13 dollars 50 cents", or first standalone number in remainder
        if let match = dollarRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text) {
            result.payout = Double(text[r])
        } else if let match = dcRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r1 = Range(match.range(at: 1), in: text),
                  let dollars = Double(text[r1]) {
            var cents = 0.0
            if match.range(at: 2).location != NSNotFound,
               let r2 = Range(match.range(at: 2), in: text),
               let c = Double(text[r2]) {
                cents = c / 100.0
            }
            result.payout = dollars + cents
        } else if let match = firstNumRegex.firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)),
                  let r = Range(match.range(at: 1), in: remainder) {
            result.payout = Double(remainder[r])
        }

        // 4. Optional spoken deadhead & order type
        if text.contains("round trip") {
            result.deadhead = .roundTrip
        } else if text.contains("edge") || text.contains("out of zone") {
            result.deadhead = .edge
        }

        if text.contains("shop") {
            result.orderType = .shop
        } else if text.contains("stack") {
            result.orderType = .stack
        }

        return result
    }

    /// Runs Vision OCR on a DoorDash offer screenshot and parses payout, miles, and minutes.
    static func recognizeOfferFromImageData(_ data: Data) async -> ParsedVoiceOffer? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: " ")
                let parsed = Self.parseSpokenOffer(joined)
                if parsed.payout == nil && parsed.miles == nil && parsed.minutes == nil {
                    cont.resume(returning: nil)
                } else {
                    cont.resume(returning: parsed)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
