import SwiftUI
import UIKit

struct CaptureLibraryScreen: View {
    @ObservedObject private var library: CaptureLibraryStore
    let camera: CameraModel

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    init(camera: CameraModel) {
        self.camera = camera
        _library = ObservedObject(wrappedValue: camera.library)
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.isLoading {
                    ProgressView("ライブラリを読み込んでいます…")
                } else if let loadError = library.loadError {
                    ContentUnavailableView(
                        "ライブラリを読み込めません",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if library.items.isEmpty {
                    ContentUnavailableView(
                        "撮影した画像はまだありません",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("撮影すると、ここから確認・コピー・編集できます。")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(library.items) { item in
                                NavigationLink(value: item.id) {
                                    LibraryThumbnail(item: item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    "\(item.createdAt.formatted(date: .abbreviated, time: .shortened))の撮影画像"
                                )
                            }
                        }
                        .padding(.horizontal, 3)
                        .padding(.bottom, 16)
                    }
                    .background(Color.black)
                }
            }
            .navigationTitle("撮影ライブラリ")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { itemID in
                CaptureDetailScreen(camera: camera, itemID: itemID)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct LibraryThumbnail: View {
    let item: CaptureLibraryItem

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: item.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.width)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Text(item.createdAt, format: .dateTime.hour().minute())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(6)
                }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white.opacity(0.06))
    }
}

private struct CaptureDetailScreen: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject private var library: CaptureLibraryStore
    let itemID: UUID

    @State private var image: UIImage?
    @State private var editorCapture: EditableCapture?
    @State private var isLoading = true
    @State private var isPreparingEditor = false
    @State private var errorMessage: String?

    init(camera: CameraModel, itemID: UUID) {
        self.camera = camera
        self.itemID = itemID
        _library = ObservedObject(wrappedValue: camera.library)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(16)
                    }
                } else if isLoading {
                    ProgressView("画像を読み込んでいます…")
                } else {
                    ContentUnavailableView(
                        "画像を開けません",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text(errorMessage ?? "撮影画像が見つかりません。")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if image != nil {
                HStack(spacing: 12) {
                    Button(action: copyImage) {
                        Label("コピー", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: prepareEditor) {
                        HStack(spacing: 8) {
                            if isPreparingEditor {
                                ProgressView()
                            } else {
                                Image(systemName: "crop.rotate")
                            }
                            Text("編集")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                    .disabled(isPreparingEditor)
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: library.item(withID: itemID)?.modifiedAt) {
            await loadImage()
        }
        .fullScreenCover(item: $editorCapture, onDismiss: {
            Task { await loadImage() }
        }) { capture in
            CropEditorScreen(camera: camera, capture: capture)
        }
        .alert(
            "編集を開始できません",
            isPresented: Binding(
                get: { errorMessage != nil && image != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "不明なエラー")
        }
    }

    private var navigationTitle: String {
        library.item(withID: itemID)?.createdAt.formatted(
            date: .abbreviated,
            time: .shortened
        ) ?? "撮影画像"
    }

    @MainActor
    private func loadImage() async {
        isLoading = true
        do {
            image = try await library.processedImage(for: itemID)
            errorMessage = nil
        } catch {
            image = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func copyImage() {
        guard let image else { return }
        camera.copyImage(image)
    }

    private func prepareEditor() {
        guard !isPreparingEditor else { return }
        isPreparingEditor = true
        Task {
            do {
                let capture = try await library.editableCapture(for: itemID)
                await MainActor.run {
                    isPreparingEditor = false
                    editorCapture = capture
                }
            } catch {
                await MainActor.run {
                    isPreparingEditor = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
