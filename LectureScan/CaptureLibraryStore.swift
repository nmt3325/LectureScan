import Foundation
import UIKit

struct CaptureLibraryItem: Identifiable {
    let id: UUID
    let createdAt: Date
    let modifiedAt: Date
    let thumbnail: UIImage
}

final class CaptureLibraryStore: ObservableObject {
    @Published private(set) var items: [CaptureLibraryItem] = []
    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?

    private let fileManager: FileManager
    private let rootDirectory: URL
    private let ioQueue = DispatchQueue(
        label: "dev.nmt3325.LectureScan.capture-library",
        qos: .userInitiated
    )

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        self.rootDirectory = rootDirectory
            ?? applicationSupport
                .appendingPathComponent("LectureScan", isDirectory: true)
                .appendingPathComponent("Captures", isDirectory: true)
        reload()
    }

    func save(capture: EditableCapture, processedImage: UIImage) throws {
        try ioQueue.sync {
            try ensureDirectory()

            let directory = captureDirectory(for: capture.id)
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            guard let processedData = processedImage.jpegData(compressionQuality: 0.96),
                  let thumbnailData = makeThumbnail(from: processedImage)
                    .jpegData(compressionQuality: 0.88) else {
                throw CaptureLibraryError.imageEncodingFailed
            }

            let sourceURL = sourceURL(for: capture.id)
            if !fileManager.fileExists(atPath: sourceURL.path) {
                guard let sourceData = capture.sourceImage.jpegData(compressionQuality: 0.96) else {
                    throw CaptureLibraryError.imageEncodingFailed
                }
                try sourceData.write(to: sourceURL, options: .atomic)
            }
            try processedData.write(to: processedURL(for: capture.id), options: .atomic)
            try thumbnailData.write(to: thumbnailURL(for: capture.id), options: .atomic)

            var records = try readRecords()
            let now = Date()
            let createdAt = records.first(where: { $0.id == capture.id })?.createdAt ?? now
            let record = CaptureRecord(
                id: capture.id,
                createdAt: createdAt,
                modifiedAt: now,
                automaticQuadrilateral: capture.automaticQuadrilateral,
                selectedQuadrilateral: capture.selectedQuadrilateral
            )

            if let index = records.firstIndex(where: { $0.id == capture.id }) {
                records[index] = record
            } else {
                records.append(record)
            }
            records.sort { $0.createdAt > $1.createdAt }
            try writeRecords(records)
            publish(items: try makeItems(from: records), error: nil)
        }
    }

    func processedImage(for id: UUID) async throws -> UIImage {
        try await performIO {
            guard self.record(withID: id, in: try self.readRecords()) != nil else {
                throw CaptureLibraryError.itemNotFound
            }
            return try self.readImage(at: self.processedURL(for: id))
        }
    }

    func editableCapture(for id: UUID) async throws -> EditableCapture {
        try await performIO {
            let records = try self.readRecords()
            guard let record = self.record(withID: id, in: records) else {
                throw CaptureLibraryError.itemNotFound
            }
            let sourceImage = try self.readImage(at: self.sourceURL(for: id))
            return EditableCapture(
                id: record.id,
                sourceImage: sourceImage,
                automaticQuadrilateral: record.automaticQuadrilateral,
                selectedQuadrilateral: record.selectedQuadrilateral
            )
        }
    }

    func item(withID id: UUID) -> CaptureLibraryItem? {
        items.first { $0.id == id }
    }

    func reload() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.ensureDirectory()
                let records = try self.readRecords()
                    .sorted { $0.createdAt > $1.createdAt }
                self.publish(items: try self.makeItems(from: records), error: nil)
            } catch {
                self.publish(items: [], error: error.localizedDescription)
            }
        }
    }

    private func performIO<T>(
        _ operation: @escaping () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    private func readRecords() throws -> [CaptureRecord] {
        let url = rootDirectory.appendingPathComponent("index.json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([CaptureRecord].self, from: data)
        } catch {
            throw CaptureLibraryError.invalidIndex(error)
        }
    }

    private func writeRecords(_ records: [CaptureRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(
            to: rootDirectory.appendingPathComponent("index.json"),
            options: .atomic
        )
    }

    private func makeItems(from records: [CaptureRecord]) throws -> [CaptureLibraryItem] {
        try records.map { record in
            CaptureLibraryItem(
                id: record.id,
                createdAt: record.createdAt,
                modifiedAt: record.modifiedAt,
                thumbnail: try readImage(at: thumbnailURL(for: record.id))
            )
        }
    }

    private func record(withID id: UUID, in records: [CaptureRecord]) -> CaptureRecord? {
        records.first { $0.id == id }
    }

    private func readImage(at url: URL) throws -> UIImage {
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw CaptureLibraryError.imageReadFailed
        }
        return image
    }

    private func makeThumbnail(from image: UIImage) -> UIImage {
        let maximumDimension: CGFloat = 480
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maximumDimension else { return image }

        let scale = maximumDimension / longestSide
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func captureDirectory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func sourceURL(for id: UUID) -> URL {
        captureDirectory(for: id).appendingPathComponent("source.jpg")
    }

    private func processedURL(for id: UUID) -> URL {
        captureDirectory(for: id).appendingPathComponent("processed.jpg")
    }

    private func thumbnailURL(for id: UUID) -> URL {
        captureDirectory(for: id).appendingPathComponent("thumbnail.jpg")
    }

    private func publish(items: [CaptureLibraryItem], error: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.items = items
            self?.loadError = error
            self?.isLoading = false
        }
    }
}

private struct CaptureRecord: Codable {
    let id: UUID
    let createdAt: Date
    let modifiedAt: Date
    let automaticQuadrilateral: DetectedQuadrilateral?
    let selectedQuadrilateral: DetectedQuadrilateral
}

private enum CaptureLibraryError: LocalizedError {
    case imageEncodingFailed
    case imageReadFailed
    case invalidIndex(Error)
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "撮影画像をライブラリ用に変換できませんでした。"
        case .imageReadFailed:
            return "ライブラリの画像を読み込めませんでした。"
        case .invalidIndex:
            return "撮影ライブラリの一覧データが壊れています。"
        case .itemNotFound:
            return "選択した撮影画像が見つかりません。"
        }
    }
}
