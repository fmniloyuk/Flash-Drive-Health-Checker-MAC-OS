import AppKit
import FlashScopeCore
import UniformTypeIdentifiers

@MainActor
enum ReportExportController {
    enum Format { case pdf, json, text }

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
            panel.nameFieldStringValue = baseName + ".txt"
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

    private static func safeName(_ value: String) -> String {
        value.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
