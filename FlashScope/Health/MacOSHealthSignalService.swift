import Foundation
import FlashScopeCore

struct MacOSHealthSignalService: HealthSignalService {
    let adapter: DiskUtilityAdapter

    init(adapter: DiskUtilityAdapter = .init()) {
        self.adapter = adapter
    }

    func signals(for drive: PhysicalDrive) async -> [HealthSignal] {
        do {
            let info = try await adapter.info(for: drive.bsdName)
            let smart: EvidenceAvailability<String>
            if let status = info.smartStatus, !status.isEmpty {
                if status.localizedCaseInsensitiveContains("not supported") {
                    smart = .unsupported("Not supported or not exposed")
                } else {
                    smart = .available(status)
                }
            } else {
                smart = .unsupported("Not supported or not exposed")
            }
            return [
                .init(kind: .smart, availability: smart),
                .init(kind: .temperature, availability: .unsupported("Temperature is not exposed for most USB flash drives"))
            ]
        } catch {
            return [.init(kind: .smart, availability: .unavailable("Hardware-health query unavailable"))]
        }
    }
}
