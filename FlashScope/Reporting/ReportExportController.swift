import AppKit
import FlashScopeCore
import UniformTypeIdentifiers

@MainActor
enum ReportExportController {
    enum Format { case pdf, json, text }

    private struct AnonymousBaselineContribution: Codable {
        var schemaVersion = "1.0"
        var generatedAt: Date
        var deviceIdentityHash: String
        var manufacturer: String?
        var model: String?
        var capacityBytes: UInt64
        var filesystem: String?
        var usbSpecification: String?
        var negotiatedMegabitsPerSecond: Double?
        var vendorID: UInt16?
        var productID: UInt16?
        var hubOrAdapterDetected: Bool?
        var writeMegabytesPerSecond: Double?
        var readMegabytesPerSecond: Double?
        var writeVariation: Double?
        var readVariation: Double?
        var integrity: String?
        var ioErrorCount: Int?
        var filesystemVerification: String
        var classification: String
        var diagnosticConfidence: Double
        var findingCategories: [String]
    }

    static func export(session: TestSession, format: Format, reports: any ReportGenerator, redactIdentifiers: Bool) throws {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let baseName = "FlashScope-\(safeName(session.volume.name))-\(dateStamp(session.timestamp))"
        let data: Data
        switch format {
        case .pdf:
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = baseName + ".pdf"
            data = try PDFReportRenderer().render(session: session, options: .init(redactSerialNumber: redactIdentifiers, redactUsernamesInPaths: true))
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = baseName + ".json"
            data = try reports.jsonReport(for: session, options: .init(redactSerialNumber: redactIdentifiers, redactUsernamesInPaths: true))
        case .text:
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = baseName + "-evidence-certificate.txt"
            data = Data(reports.plainTextReport(for: session, options: .init(redactSerialNumber: redactIdentifiers, redactUsernamesInPaths: true)).utf8)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: [.atomic])
    }

    static func copySupportSummary(session: TestSession, reports: any ReportGenerator, redactIdentifiers: Bool) {
        let string = reports.plainTextReport(for: session, options: .init(redactSerialNumber: redactIdentifiers, redactUsernamesInPaths: true))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    static func copyAnonymousContribution(session: TestSession) throws {
        let benchmark = session.benchmark
        let contribution = AnonymousBaselineContribution(
            generatedAt: Date(),
            deviceIdentityHash: session.driveIdentityHash,
            manufacturer: session.drive.manufacturer.value,
            model: session.drive.model.value,
            capacityBytes: session.drive.capacityBytes,
            filesystem: session.volume.filesystem.value?.rawValue,
            usbSpecification: (session.connection.declaredSpecification.value ?? session.drive.capabilities.declaredUSBSpecification.value)?.rawValue,
            negotiatedMegabitsPerSecond: session.connection.negotiatedSpeed.value?.megabitsPerSecond,
            vendorID: session.connection.vendorID.value,
            productID: session.connection.productID.value,
            hubOrAdapterDetected: session.connection.hubOrAdapterDetected.value,
            writeMegabytesPerSecond: benchmark?.writeMegabytesPerSecond,
            readMegabytesPerSecond: benchmark?.readMegabytesPerSecond,
            writeVariation: benchmark?.writeStatistics.coefficientOfVariation,
            readVariation: benchmark?.readStatistics.coefficientOfVariation,
            integrity: benchmark?.integrity.status.rawValue,
            ioErrorCount: benchmark?.ioErrorCount,
            filesystemVerification: session.filesystemCheck.status.rawValue,
            classification: session.diagnosis.assessment.classification.rawValue,
            diagnosticConfidence: session.diagnosis.assessment.confidence,
            findingCategories: session.diagnosis.findings.map { $0.category.rawValue }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(contribution)
        let string = String(decoding: data, as: UTF8.self)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private static func safeName(_ value: String) -> String {
        value.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
