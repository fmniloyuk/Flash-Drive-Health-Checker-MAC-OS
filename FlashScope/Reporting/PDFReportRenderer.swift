import AppKit
import CoreText
import FlashScopeCore
import Foundation

struct PDFReportRenderer {
    enum RenderError: Error { case contextCreationFailed }

    func render(session: TestSession, options: ReportRedactionOptions) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw RenderError.contextCreationFailed }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw RenderError.contextCreationFailed }

        let content = makeContent(session: session, options: options)
        let framesetter = CTFramesetterCreateWithAttributedString(content)
        var location = 0
        var page = 1
        while location < CFAttributedStringGetLength(content) {
            context.beginPDFPage(nil)
            drawHeader(in: context, page: page, session: session)
            let bodyRect = CGRect(x: 54, y: 62, width: 504, height: 650)
            let path = CGPath(rect: bodyRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 { break }
            location += visible.length
            drawFooter(in: context, page: page)
            context.endPDFPage()
            page += 1
        }
        context.closePDF()
        return data as Data
    }

    private func makeContent(session: TestSession, options: ReportRedactionOptions) -> CFAttributedString {
        let output = NSMutableAttributedString()
        let title = attributes(size: 22, weight: .bold, color: .labelColor, spacing: 8)
        let heading = attributes(size: 14, weight: .semibold, color: .labelColor, spacing: 5)
        let body = attributes(size: 10.5, weight: .regular, color: .labelColor, spacing: 4)
        let secondary = attributes(size: 9.5, weight: .regular, color: .secondaryLabelColor, spacing: 4)

        append("Diagnostic summary\n", to: output, attrs: title)
        append("Health: \(session.diagnosis.assessment.classification.rawValue)\n", to: output, attrs: heading)
        append("\(session.diagnosis.assessment.summary)\n\n", to: output, attrs: body)

        append("Device & connection\n", to: output, attrs: heading)
        append("Device: \(session.drive.displayName)\n", to: output, attrs: body)
        append("Capacity: \(StorageFormatting.bytes(session.drive.capacityBytes))\n", to: output, attrs: body)
        append("Serial: \(options.redactSerialNumber ? "Redacted" : session.drive.serialNumber.value ?? "Unavailable")\n", to: output, attrs: body)
        append("Declared USB specification: \(session.connection.declaredSpecification.value?.rawValue ?? "Unavailable")\n", to: output, attrs: body)
        append("Negotiated link: \(session.connection.negotiatedSpeed.value?.label ?? "Unavailable")\n", to: output, attrs: body)
        if let expected = session.diagnosis.expectedPracticalRangeMBps {
            append(String(format: "Expected practical sequential read guidance: %.0f–%.0f MB/s\n", expected.lowerBound, expected.upperBound), to: output, attrs: body)
        }
        append("\n", to: output, attrs: body)

        append("Volume & filesystem\n", to: output, attrs: heading)
        let mount = options.redactUsernamesInPaths ? DefaultReportGenerator.redactUsername(in: session.volume.mountPath) : session.volume.mountPath
        append("Volume: \(session.volume.name)\nMount: \(mount)\n", to: output, attrs: body)
        append("Filesystem: \(session.volume.filesystem.value?.rawValue ?? "Unavailable")\n", to: output, attrs: body)
        append("Free space: \(StorageFormatting.bytes(session.volume.availableBytes)) of \(StorageFormatting.bytes(session.volume.capacityBytes))\n", to: output, attrs: body)
        append("Verification: \(session.filesystemCheck.status.rawValue) — \(session.filesystemCheck.summary)\n\n", to: output, attrs: body)

        append("Performance & integrity\n", to: output, attrs: heading)
        if let benchmark = session.benchmark {
            append(String(format: "Sequential write: %.1f MB/s\nSequential read: %.1f MB/s\n", benchmark.writeMegabytesPerSecond, benchmark.readMegabytesPerSecond), to: output, attrs: body)
            append("Benchmark size: \(StorageFormatting.bytes(benchmark.configuration.sizeBytes))\n", to: output, attrs: body)
            append("Durable write flush included: \(benchmark.durableFlushIncluded ? "Yes" : "No")\n", to: output, attrs: body)
            append("Integrity: \(benchmark.integrity.status.rawValue) (SHA-256)\n", to: output, attrs: body)
            append("Cleanup: \(benchmark.cleanupStatus.rawValue)\n", to: output, attrs: body)
            append("Read-cache note: standard reads are file-level and may be affected by macOS caching; they are not presented as raw media reads.\n", to: output, attrs: secondary)
        } else {
            append("Performance benchmark not run.\n", to: output, attrs: secondary)
        }
        append("\n", to: output, attrs: body)

        append("Prioritized findings\n", to: output, attrs: heading)
        if session.diagnosis.findings.isEmpty { append("No findings beyond the available assessment.\n", to: output, attrs: body) }
        for (index, finding) in session.diagnosis.findings.enumerated() {
            append("\(index + 1). \(finding.title) [\(severityName(finding.severity)), \(Int(finding.confidence * 100))% confidence]\n", to: output, attrs: body)
            append("\(finding.explanation)\nImpact: \(finding.expectedImpact)\nAction: \(finding.recommendedAction)\n", to: output, attrs: body)
            if let caveat = finding.caveat { append("Caveat: \(caveat)\n", to: output, attrs: secondary) }
            append("\n", to: output, attrs: body)
        }

        append("Limitations & methodology\n", to: output, attrs: heading)
        for limitation in session.diagnosis.limitations { append("• \(limitation)\n", to: output, attrs: secondary) }
        append("• Benchmark data is pseudo-random/non-zero by default to avoid compression-distorted results.\n", to: output, attrs: secondary)
        append("• Write timing includes synchronization to durable storage.\n", to: output, attrs: secondary)
        append("• The configured benchmark amount is written once and adds a small amount of flash wear.\n", to: output, attrs: secondary)
        append("• FlashScope never formats, repartitions, repairs, force-unmounts, or raw-writes a drive.\n\n", to: output, attrs: secondary)

        append("Technical appendix\n", to: output, attrs: heading)
        append("Report schema: \(JSONReportEnvelope.currentSchemaVersion)\n", to: output, attrs: secondary)
        append("Physical BSD identifier: \(session.drive.bsdName)\nVolume BSD identifier: \(session.volume.bsdName)\n", to: output, attrs: secondary)
        append("Filesystem verification exit status: \(session.filesystemCheck.exitStatus.map { String($0) } ?? "Unavailable")\n", to: output, attrs: secondary)
        append("Device identity for history is a local SHA-256 hash; clear serial numbers are not stored as the identity key.\n", to: output, attrs: secondary)
        return output
    }

    private func drawHeader(in context: CGContext, page: Int, session: TestSession) {
        context.saveGState()
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 746, width: 612, height: 46))
        drawLine("FlashScope", at: CGPoint(x: 54, y: 762), font: .systemFont(ofSize: 18, weight: .semibold), color: .white, context: context)
        drawLine("USB storage diagnostic report", at: CGPoint(x: 160, y: 764), font: .systemFont(ofSize: 10, weight: .regular), color: .white.withAlphaComponent(0.9), context: context)
        context.restoreGState()
    }

    private func drawFooter(in context: CGContext, page: Int) {
        drawLine("Diagnostic evidence, not a substitute for backups", at: CGPoint(x: 54, y: 34), font: .systemFont(ofSize: 8.5), color: .secondaryLabelColor, context: context)
        drawLine("Page \(page)", at: CGPoint(x: 515, y: 34), font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .regular), color: .secondaryLabelColor, context: context)
    }

    private func drawLine(_ text: String, at point: CGPoint, font: NSFont, color: NSColor, context: CGContext) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private func attributes(size: CGFloat, weight: NSFont.Weight, color: NSColor, spacing: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = spacing
        paragraph.lineSpacing = 1.5
        return [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private func append(_ string: String, to output: NSMutableAttributedString, attrs: [NSAttributedString.Key: Any]) {
        output.append(NSAttributedString(string: string, attributes: attrs))
    }

    private func severityName(_ severity: FindingSeverity) -> String {
        switch severity { case .info: "Info"; case .low: "Low"; case .medium: "Medium"; case .high: "High"; case .critical: "Critical" }
    }
}
