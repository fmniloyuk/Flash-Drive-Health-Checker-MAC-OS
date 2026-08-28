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
        guard let mediaService = matchingMediaService(forBSDName: drive.bsdName) else {
            logger.info("Could not locate the IOMedia registry entry for \(drive.bsdName, privacy: .public)")
            return .init(
                declaredSpecification: .unavailable("The selected disk could not be matched to its IORegistry media object"),
                negotiatedSpeed: .unavailable("USB link information could not be associated with the selected disk")
            )
        }
        defer { IOObjectRelease(mediaService) }
        return inspectUSBAncestors(startingAt: mediaService)
    }

    /// Finds the exact IOMedia object for the selected BSD disk name.
    ///
    /// The previous implementation used a `defer` while mutating the iterator's
    /// service variable. That could release the next registry object rather than
    /// the object just inspected. Keeping each IOObject lifetime explicit avoids
    /// invalid registry handles and makes USB ancestry lookup deterministic.
    private func matchingMediaService(forBSDName bsdName: String) -> io_service_t? {
        guard let matching = IOServiceMatching("IOMedia") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { return nil }
            if let foundName = property("BSD Name", service: service) as? String, foundName == bsdName {
                // Caller owns the +1 reference returned by IOIteratorNext.
                return service
            }
            IOObjectRelease(service)
        }
    }

    private func inspectUSBAncestors(startingAt service: io_registry_entry_t) -> USBConnection {
        var current = service
        var ownedCurrent = false
        var topology: [USBTopologyNode] = []
        var usbPropertySets: [[String: Any]] = []
        var hubDetected = false

        // Walk the complete IOService ancestry. USB bridges differ significantly:
        // useful properties may live on IOUSBHostDevice, an interface/nub, a hub
        // node, or another USB-labelled parent. We therefore collect conservative
        // evidence from every USB-relevant ancestor rather than depending on one
        // exact class name.
        while true {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            if ownedCurrent { IOObjectRelease(current) }
            current = parent
            ownedCurrent = true

            let className = ioClassName(current)
            let registryName = ioRegistryName(current)
            let props = properties(current)
            let usbRelevant = isUSBRelevant(className: className, registryName: registryName, properties: props)

            if usbRelevant {
                usbPropertySets.append(props)
                topology.append(.init(
                    id: "\(current)",
                    name: registryName.isEmpty ? className : registryName,
                    kind: className
                ))
            }
            if className.localizedCaseInsensitiveContains("hub") || registryName.localizedCaseInsensitiveContains("hub") {
                hubDetected = true
            }
        }
        if ownedCurrent { IOObjectRelease(current) }

        guard !usbPropertySets.isEmpty else {
            logger.info("No USB-relevant ancestor properties were exposed for selected removable drive")
            return .init(
                declaredSpecification: .unavailable("No USB device ancestor was exposed for this disk"),
                negotiatedSpeed: .unavailable("Negotiated USB speed was not exposed for this disk"),
                topology: topology,
                hubOrAdapterDetected: topology.isEmpty ? .unavailable("USB topology unavailable") : .available(hubDetected)
            )
        }

        // bcdUSB is the USB specification release. Do not fall back to bcdDevice /
        // "USB Device Release Number", which describes the product release and is
        // not evidence of USB 2/3/4 capability.
        let bcdUSB = number(firstProperty(["bcdUSB"], in: usbPropertySets))
        let declared = USBDescriptorParser.specification(fromBCDUSB: bcdUSB)

        let speedProperty = firstProperty(["USBSpeed", "USB Speed", "Device Speed"], in: usbPropertySets)
        let negotiated: EvidenceAvailability<USBLinkSpeed>
        if let text = speedProperty as? String {
            negotiated = USBDescriptorParser.negotiatedSpeed(fromDescriptor: text)
        } else if let numeric = number(speedProperty) {
            negotiated = USBDescriptorParser.negotiatedSpeed(fromNumericDescriptor: numeric)
        } else {
            negotiated = .unavailable("The USB ancestors were found, but macOS did not expose a recognized negotiated-speed property")
        }

        let vendor = number(firstProperty(["idVendor", "USB Vendor ID", "VendorID"], in: usbPropertySets))
            .map { UInt16(truncatingIfNeeded: $0) }
        let product = number(firstProperty(["idProduct", "USB Product ID", "ProductID"], in: usbPropertySets))
            .map { UInt16(truncatingIfNeeded: $0) }
        let location = number(firstProperty(["locationID", "LocationID"], in: usbPropertySets))
            .map { String(format: "0x%08X", $0) }

        let allocated = number(firstProperty(
            ["Current Required", "USB Power", "Requested Power", "Device Power"],
            in: usbPropertySets
        )).map { Int(clamping: $0) }
        let available = number(firstProperty(
            ["AAPL,current-available", "Current Available", "Bus Power Available", "Available Power"],
            in: usbPropertySets
        )).map { Int(clamping: $0) }

        return USBConnection(
            declaredSpecification: declared,
            negotiatedSpeed: negotiated,
            vendorID: vendor.map { .available($0) } ?? .unavailable("Vendor identifier not exposed by the USB device/bridge"),
            productID: product.map { .available($0) } ?? .unavailable("Product identifier not exposed by the USB device/bridge"),
            portPath: location.map { .available($0) } ?? .unavailable("USB location identifier not exposed"),
            topology: Array(topology.reversed()),
            hubOrAdapterDetected: .available(hubDetected),
            allocatedMilliAmps: allocated.map { .available($0) } ?? .unavailable("Requested USB current not exposed"),
            availableMilliAmps: available.map { .available($0) } ?? .unavailable("Available USB bus current not exposed")
        )
    }

    private func isUSBRelevant(className: String, registryName: String, properties: [String: Any]) -> Bool {
        if className.localizedCaseInsensitiveContains("usb") || registryName.localizedCaseInsensitiveContains("usb") {
            return true
        }
        let evidenceKeys = [
            "bcdUSB", "USBSpeed", "USB Speed", "idVendor", "idProduct",
            "USB Vendor ID", "USB Product ID", "locationID", "AAPL,current-available"
        ]
        return evidenceKeys.contains { properties[$0] != nil }
    }

    private func firstProperty(_ keys: [String], in propertySets: [[String: Any]]) -> Any? {
        for properties in propertySets {
            for key in keys {
                if let value = properties[key] { return value }
            }
        }
        return nil
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
        if let value = value as? UInt32 { return UInt64(value) }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("0x") {
                return UInt64(trimmed.dropFirst(2), radix: 16)
            }
            return UInt64(trimmed)
        }
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
