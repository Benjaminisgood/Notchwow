import AppKit
import Foundation
import MarkdownEngine
import UniformTypeIdentifiers

final class LocalImageStore: EmbeddedImageFileProvider, @unchecked Sendable {
    private struct ImageAssetRecord: Codable {
        var id: String
        var displayName: String
        var storedFilename: String
        var relativePath: String?
        var originalPath: String?
        var sourceKind: String
        var createdAt: Date
    }

    private let markdownRootURL: URL
    private let directoryURL: URL
    private let manifestURL: URL
    private let lock = NSLock()
    private var records: [String: ImageAssetRecord]
    private var version = 0

    init() {
        WorkspacePaths.ensureDirectories()
        markdownRootURL = WorkspacePaths.markdownRoot
        directoryURL = WorkspacePaths.markdownAttachments
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        manifestURL = directoryURL.appendingPathComponent("manifest.json")
        records = Self.loadRecords(from: manifestURL)
    }

    func saveImage(from pasteboard: NSPasteboard) -> String? {
        saveAttachment(from: pasteboard)
    }

    func saveAttachment(from pasteboard: NSPasteboard) -> String? {
        let fileEmbeds = fileURLs(from: pasteboard).compactMap { fileURL in
            saveFileAttachment(from: fileURL)
        }

        if !fileEmbeds.isEmpty {
            return fileEmbeds.joined(separator: "\n")
        }

        guard let pngData = PasteboardImageReader.imageData(from: pasteboard) else {
            return nil
        }

        return saveImageData(
            data: pngData,
            originalName: "pasted-image",
            preferredExtension: "png",
            originalFileURL: nil,
            sourceKind: "clipboardImage"
        )
    }

    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        let candidateNames = [reference.id, reference.name].compactMap { $0 }

        for candidateName in candidateNames {
            let url = resolvedFileURL(for: candidateName)
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }

    func storedFileURL(for reference: EmbeddedImageRequest) -> URL? {
        guard let candidateName = recordCandidateNames(for: reference).first(where: { !$0.isEmpty }) else {
            return nil
        }

        let fallbackURL = resolvedFileURL(for: candidateName)
        return FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
    }

    func originalFileURL(for reference: EmbeddedImageRequest) -> URL? {
        guard let candidateName = recordCandidateNames(for: reference).first(where: { !$0.isEmpty }) else {
            return nil
        }

        lock.lock()
        let path = records[candidateName]?.originalPath
        lock.unlock()

        guard let path else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fingerprint() -> AnyHashable {
        lock.lock()
        defer { lock.unlock() }
        return version
    }

    private func saveFileAttachment(from fileURL: URL) -> String? {
        guard fileURL.isFileURL else { return nil }

        let displayName = sanitizedDisplayName(fileURL.deletingPathExtension().lastPathComponent)
        let fileExtension = fileURL.pathExtension.isEmpty ? "bin" : fileURL.pathExtension
        let isImage = Self.isImageFile(fileURL)

        if isAlreadyInAttachmentDirectory(fileURL),
           FileManager.default.fileExists(atPath: fileURL.path) {
            let relativePath = relativeAttachmentPath(forStoredFilename: fileURL.lastPathComponent)
            recordAttachment(
                displayName: displayName,
                storedFilename: fileURL.lastPathComponent,
                relativePath: relativePath,
                originalFileURL: fileURL,
                sourceKind: "existingAttachment"
            )
            return markdownReference(displayName: displayName, relativePath: relativePath, isImage: isImage)
        }

        guard let targetURL = copyFileAttachment(from: fileURL, displayName: displayName, fileExtension: fileExtension) else {
            return nil
        }

        let relativePath = relativeAttachmentPath(forStoredFilename: targetURL.lastPathComponent)
        recordAttachment(
            displayName: displayName,
            storedFilename: targetURL.lastPathComponent,
            relativePath: relativePath,
            originalFileURL: fileURL,
            sourceKind: isImage ? "imageFile" : "mediaFile"
        )

        return markdownReference(displayName: displayName, relativePath: relativePath, isImage: isImage)
    }

    private func saveImageData(
        data: Data,
        originalName: String,
        preferredExtension: String,
        originalFileURL: URL?,
        sourceKind: String
    ) -> String? {
        let displayName = sanitizedDisplayName(originalName)
        let url = WorkspacePaths.uniquedFileURL(
            stem: displayName,
            fileExtension: preferredExtension,
            in: directoryURL
        )
        let relativePath = relativeAttachmentPath(forStoredFilename: url.lastPathComponent)

        do {
            try data.write(to: url, options: .atomic)
            recordAttachment(
                displayName: displayName,
                storedFilename: url.lastPathComponent,
                relativePath: relativePath,
                originalFileURL: originalFileURL,
                sourceKind: sourceKind
            )
            return "![[\(relativePath)]]"
        } catch {
            return nil
        }
    }

    private func recordCandidateNames(for reference: EmbeddedImageRequest) -> [String] {
        [reference.id, reference.name].compactMap { $0 }
    }

    private func resolvedFileURL(for rawReference: String) -> URL {
        let reference = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        let record = records[reference]
        lock.unlock()

        if let record {
            return directoryURL.appendingPathComponent(record.storedFilename)
        }

        if reference.hasPrefix("/") {
            return URL(fileURLWithPath: reference)
        }

        if reference.hasPrefix("attachments/") {
            return markdownRootURL.appendingPathComponent(reference, isDirectory: false)
        }

        if !URL(fileURLWithPath: reference).pathExtension.isEmpty {
            let markdownRelativeURL = markdownRootURL.appendingPathComponent(reference, isDirectory: false)
            if FileManager.default.fileExists(atPath: markdownRelativeURL.path) {
                return markdownRelativeURL
            }
            return directoryURL.appendingPathComponent(reference, isDirectory: false)
        }

        return directoryURL.appendingPathComponent("\(reference).png")
    }

    private func copyFileAttachment(from fileURL: URL, displayName: String, fileExtension: String) -> URL? {
        let targetURL = WorkspacePaths.uniquedFileURL(
            stem: displayName,
            fileExtension: fileExtension,
            in: directoryURL
        )

        do {
            try FileManager.default.copyItem(at: fileURL, to: targetURL)
            return targetURL
        } catch {
            return nil
        }
    }

    private func recordAttachment(
        displayName: String,
        storedFilename: String,
        relativePath: String,
        originalFileURL: URL?,
        sourceKind: String
    ) {
        let record = ImageAssetRecord(
            id: UUID().uuidString,
            displayName: displayName,
            storedFilename: storedFilename,
            relativePath: relativePath,
            originalPath: originalFileURL?.path,
            sourceKind: sourceKind,
            createdAt: Date()
        )

        lock.lock()
        records[relativePath] = record
        let recordsToSave = records
        version += 1
        lock.unlock()
        saveRecords(recordsToSave)
    }

    private func markdownReference(displayName: String, relativePath: String, isImage: Bool) -> String {
        isImage ? "![[\(relativePath)]]" : "[\(displayName)](\(relativePath))"
    }

    private func sanitizedDisplayName(_ name: String) -> String {
        WorkspacePaths.sanitizedFileStem(name, fallback: "pasted-image")
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    private func isAlreadyInAttachmentDirectory(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directoryURL.standardizedFileURL.path + "/")
    }

    private func relativeAttachmentPath(forStoredFilename filename: String) -> String {
        "attachments/\(filename)"
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private static func loadRecords(from url: URL) -> [String: ImageAssetRecord] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([ImageAssetRecord].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: records.map { record in
            (record.relativePath ?? record.id, record)
        })
    }

    private func saveRecords(_ records: [String: ImageAssetRecord]) {
        let sortedRecords = records.values.sorted { $0.createdAt < $1.createdAt }
        guard let data = try? JSONEncoder().encode(sortedRecords) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
