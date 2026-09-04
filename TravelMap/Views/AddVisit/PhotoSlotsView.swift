import PhotosUI
import SwiftUI

/// The four photo slots. Optional by design — a visit saves fine with none of them.
struct PhotoSlotsView: View {
    /// Storage paths retained from an existing visit. Empty while creating a visit.
    @Binding var existingPhotoPaths: [String]
    @Binding var photos: [UIImage]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPicked = false

    private var photoCount: Int { existingPhotoPaths.count + photos.count }
    private var remainingSlots: Int { max(0, VisitsService.maxPhotos - photoCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos").font(.subheadline.weight(.medium))
                Text("optional · up to \(VisitsService.maxPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoadingPicked {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading photos")
                }
            }

            HStack(spacing: 8) {
                ForEach(0..<VisitsService.maxPhotos, id: \.self) { index in
                    slot(at: index)
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            loadPicked(items)
        }
    }

    @ViewBuilder
    private func slot(at index: Int) -> some View {
        if index < existingPhotoPaths.count {
            photoSlot(index: index) {
                StoragePhotoView(path: existingPhotoPaths[index])
            } onRemove: {
                existingPhotoPaths.remove(at: index)
            }
        } else if index < photoCount {
            let localIndex = index - existingPhotoPaths.count
            photoSlot(index: index) {
                Image(uiImage: photos[localIndex])
                    .resizable()
                    .scaledToFill()
            } onRemove: {
                photos.remove(at: localIndex)
            }
        } else if index == photoCount, remainingSlots > 0 {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: remainingSlots,
                matching: .images,
                photoLibrary: .shared()
            ) {
                EmptyPhotoSlot(showsPlus: true)
            }
            .accessibilityLabel("Add photos")
            .accessibilityHint("Up to \(remainingSlots) more")
        } else {
            EmptyPhotoSlot(showsPlus: false)
                .accessibilityHidden(true)
        }
    }

    private func photoSlot<Content: View>(
        index: Int,
        @ViewBuilder content: () -> Content,
        onRemove: @escaping () -> Void
    ) -> some View {
            // The square comes from a clear spacer that the image fills, rather than from
            // the image itself: a landscape photo would otherwise stretch its slot wider
            // than the empty ones beside it.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    content()
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            // The glyph stays small so it doesn't cover the photo; the
                            // frame around it is what makes the target hittable. Without
                            // it this is a 22pt button on a thumbnail's corner.
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove photo \(index + 1)")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Photo \(index + 1)")
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        isLoadingPicked = true
        Task {
            var loaded: [UIImage] = []
            for item in items.prefix(remainingSlots) {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            photos.append(contentsOf: loaded)
            pickerItems = []
            isLoadingPicked = false
        }
    }
}

/// A dashed placeholder slot. It's a `View` rather than a method on `PhotoSlotsView`
/// because `PhotosPicker`'s label builder runs outside the main actor.
private struct EmptyPhotoSlot: View {
    let showsPlus: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.secondarySystemBackground))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if showsPlus {
                    Image(systemName: "plus")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.quaternary)
            }
    }
}
