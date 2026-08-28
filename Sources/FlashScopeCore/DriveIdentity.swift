import Foundation

public enum PrivacyPreservingDriveIdentity {
    public static func hash(drive: PhysicalDrive) -> String {
        // Serial is used locally when available but never stored in clear text by this identity function.
        let serial = drive.serialNumber.value ?? "no-serial"
        let material = "\(drive.manufacturer.value ?? "")|\(drive.model.value ?? drive.displayName)|\(serial)|\(drive.capacityBytes)"
        return SHA256Digest.hexDigest(Data(material.utf8))
    }
}
