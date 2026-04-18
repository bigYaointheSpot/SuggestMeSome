import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PortableBackupViewModel {
    var backupExportURL: URL?
    var isGeneratingBackup = false
    var isPresentingImporter = false
    var isRestoringBackup = false
    var importPreview: PortableBackupImportPreview?
    var statusMessage: String?
    var errorMessage: String?

    private let backupService: PortableBackupService

    init(backupService: PortableBackupService? = nil) {
        self.backupService = backupService ?? PortableBackupService()
    }

    func generateBackup(context: ModelContext) {
        isGeneratingBackup = true
        defer { isGeneratingBackup = false }

        do {
            backupExportURL = try backupService.writeBackupFile(context: context)
            errorMessage = nil
            statusMessage = "Device backup is ready to share."
        } catch {
            backupExportURL = nil
            statusMessage = nil
            errorMessage = userFacingMessage(for: error)
        }
    }

    func openImporter() {
        errorMessage = nil
        statusMessage = nil
        isPresentingImporter = true
    }

    func handleImportSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            importPreview = try backupService.previewBackup(from: url)
            errorMessage = nil
            statusMessage = nil
        } catch {
            if let cocoaError = error as? CocoaError,
               cocoaError.code == .userCancelled {
                return
            }
            importPreview = nil
            statusMessage = nil
            errorMessage = userFacingMessage(for: error)
        }
    }

    func dismissImportPreview() {
        importPreview = nil
    }

    func restoreImport(
        context: ModelContext,
        accountManager: AccountManager,
        complianceStateStore: ComplianceStateStore
    ) {
        guard let preview = importPreview else { return }

        isRestoringBackup = true
        defer { isRestoringBackup = false }

        do {
            let result = try backupService.restoreBackup(
                preview.envelope,
                context: context
            )
            accountManager.reloadFromPersistence()
            complianceStateStore.reloadFromPersistence()
            importPreview = nil
            backupExportURL = nil
            errorMessage = nil
            statusMessage = "Imported backup and restored \(result.restoredManifest.totalSwiftDataRecordCount) local records."
        } catch {
            statusMessage = nil
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return "Something went wrong while handling the backup."
    }
}
