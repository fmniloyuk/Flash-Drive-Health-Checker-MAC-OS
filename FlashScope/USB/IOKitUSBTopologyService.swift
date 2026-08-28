import Foundation
import FlashScopeCore
import IOKit
import OSLog

struct IOKitUSBTopologyService: USBTopologyService {
    private let logger = Logger(subsystem: "com.example.FlashScope", category: "usb-topology")

    func connection(for drive: PhysicalDrive) async -> USBConnection {
        await Task.detached(priority: .utility) {
            inspect(drive: drive)
        }.value
    }

    private func inspect(drive: PhysicalDrive) -> USBConnection {
        guard let matching = IOServiceMatching("IOMedia") else { return .init() }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return .init() }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let bsdName = property("BSD Name", service: service) as? String, bsdName == drive.bsdName {
                return inspectUSBAncestors(startingAt: service)
            }
            service = IOIteratorNext(iterator)
        }
        logger.info("USB topology was unavailable for one selected removable drive")
        return .init(
            declaredSpecification: .unavailable("USB descriptor not exposed through IORegistry"),
            negotiatedSpeed: .unavailable("Negotiated speed not exposed through IORegistry")
        )
    }

    private func inspectUSBAncestors(startingAt service: io_registry_entry_t) -> USBConnection {
        var current = service
        var ownedCurrent = false
        var topology: [USBTopologyNode] = []
        var usbProperties: [String: Any]?
        var hubDetected = false

        while true {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            if ownedCurrent { IOObjectRelease(current) }
            current = parent
            ownedCurrent = true

            let className = ioClassName(current)
            let registryName = ioRegistryName(current)
            if className.localizedCaseInsensitiveContains("usb") || registryName.localizedCaseInsensitiveContains("usb") {
                topology.append(.init(id: "\(current)", name: registryName.isEmpty ? className : registryName, kind: className))
            }
            if className.localizedCaseInsensitiveContains("hub") || registryName.localizedCaseInsensitiveContains("hub") {
                hubDetected = true
            }
            if className == "IOUSBHostDevice" || className.localizedCaseInsensitiveContains("USBDevice") {
                usbProperties = properties(current)
                break
            }
        }
        if ownedCurrent { IOObjectRelease(current) }

        guard let props = usbProperties else {
            return .init(
                declaredSpecification: .unavailable("No USB device ancestor was exposed"),
                negotiatedSpeed: .unavailable("Negotiated speed unavailable"),
                topology: topology,
                hubOrAdapterDetected: topology.isEmpty ? .unavailable("Topology unavailable") : .available(hubDetected)
            )
        }

        let bcdUSB = number(props["bcdUSB"] ?? props["USB Device Release Number"])
        let declared = USBDescriptorParser.specification(fromBCDUSB: bcdUSB)
        let speedProperty = props["USB Speed"] ?? props["USBSpeed"] ?? props["Device Speed"]
        let negotiated: EvidenceAvailability<USBLinkSpeed>
        if let text = speedProperty as? String {
            negotiated = USBDescriptorParser.negotiatedSpeed(fromDescriptor: text)
        } else if speedProperty == nil {
            negotiated = .unavailable("Negotiated speed not exposed")
        } else {
            negotiated = .unavailable("macOS exposed a numeric speed descriptor that FlashScope does not guess at")
        }
        let vendor = number(props["idVendor"] ?? props["USB Vendor ID"]).map { UInt16(truncatingIfNeeded: $0) }
        let product = number(props["idProduct"] ?? props["USB Product ID"]).map { UInt16(truncatingIfNeeded: $0) }
        let location = number(props["locationID"]).map { String(format: "0x%08X", $0) }
        let allocated = number(props["USB Power"] ?? props["Current Required"] ?? props["Requested Power"]).map { Int(clamping: $0) }
        let available = number(props["Bus Power Available"] ?? props["Available Power"]).map { Int(clamping: $0) }

        return USBConnection(
            declaredSpecification: declared,
            negotiatedSpeed: negotiated,
            vendorID: vendor.map { .available($0) } ?? .unavailable("Vendor identifier unavailable"),
            productID: product.map { .available($0) } ?? .unavailable("Product identifier unavailable"),
            portPath: location.map { .available($0) } ?? .unavailable("Port path unavailable"),
            topology: Array(topology.reversed()),
            hubOrAdapterDetected: .available(hubDetected),
            allocatedMilliAmps: allocated.map { .available($0) } ?? .unavailable("Power allocation unavailable"),
            availableMilliAmps: available.map { .available($0) } ?? .unavailable("Available bus power unavailable")
        )
    }

    private func properties(_ service: io_registry_entry_t) -> [String: Any] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() else { return [:] }
        return dictionary as NSDictionary as? [String: Any] ?? [:]
    }

    private func property(_ key: String, service: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private func number(_ value: Any?) -> UInt64? {
        if let value = value as? NSNumber { return value.uint64Value }
        if let value = value as? UInt64 { return value }
        return nil
    }

    private func ioRegistryName(_ service: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        let status = name.withUnsafeMutableBufferPointer { buffer in
            IORegistryEntryGetName(service, buffer.baseAddress!)
        }
        guard status == KERN_SUCCESS else { return "" }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func ioClassName(_ service: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        let status = name.withUnsafeMutableBufferPointer { buffer in
            IOObjectGetClass(service, buffer.baseAddress!)
        }
        guard status == KERN_SUCCESS else { return "" }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
