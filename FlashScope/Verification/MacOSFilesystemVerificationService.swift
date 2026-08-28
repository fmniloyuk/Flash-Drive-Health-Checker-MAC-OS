import Foundation
import FlashScopeCore

struct MacOSFilesystemVerificationService: FilesystemVerificationService {
    let runner: any DiskUtilityRunning
    let mountController: any MountControlling

    init(runner: any DiskUtilityRunning = RestrictedProcessRunner(), mountController: any MountControlling = DiskArbitrationMountController()) {
        self.runner = runner
        self.mountController = mountController
    }

    func verify(volume: Volume, allowNormalUnmount: Bool) async -> FilesystemCheckResult {
        guard allowNormalUnmount else {
            return .init(
                status: .unableToRun,
                summary: "Verification was not started because this version requires explicit permission for a normal, non-forced unmount.",
                requiredUnmount: true
            )
        }
        let unmount = await mountController.normalUnmount(volume)
        guard unmount.succeeded else {
            return .init(
                status: .unableToRun,
                summary: "The volume could not be unmounted normally. Close files and Finder windows using the volume, then try again.",
                exitStatus: unmount.status,
                verificationTool: "diskutil verifyVolume",
                requiredUnmount: true,
                remountedSuccessfully: nil
            )
        }

        do {
            let command = try await runner.run(.verifyVolume(volume.bsdName))
            let remount = await mountController.mount(volume)
            if command.status == 0 {
                return .init(
                    status: .passed,
                    summary: "Read-only filesystem verification completed without reported errors.",
                    exitStatus: command.status,
                    verificationTool: "diskutil verifyVolume",
                    requiredUnmount: true,
                    remountedSuccessfully: remount.succeeded
                )
            }
            return .init(
                status: .issuesDetected,
                summary: "Filesystem verification completed and reported problems. FlashScope did not attempt a repair.",
                exitStatus: command.status,
                verificationTool: "diskutil verifyVolume",
                requiredUnmount: true,
                remountedSuccessfully: remount.succeeded
            )
        } catch RestrictedProcessError.executableUnavailable {
            let remount = await mountController.mount(volume)
            return .init(status: .toolUnavailable, summary: "The macOS verification tool is unavailable.", verificationTool: "diskutil verifyVolume", requiredUnmount: true, remountedSuccessfully: remount.succeeded)
        } catch {
            let remount = await mountController.mount(volume)
            return .init(status: .unableToRun, summary: "Filesystem verification could not be completed.", verificationTool: "diskutil verifyVolume", requiredUnmount: true, remountedSuccessfully: remount.succeeded)
        }
    }
}
