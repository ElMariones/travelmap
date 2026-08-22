import PhotosUI
import SwiftUI

/// The four photo slots. Optional by design — a visit saves fine with none of them.
struct PhotoSlotsView: View {
    @Binding var photos: [UIImage]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPicked = false

    private var remainingSlots: Int { max(0, VisitsService.maxPhotos - photos.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos").font(.subheadline.weight(.medium))
                Text("optional · up to \(VisitsService.maxPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoadingPicked { ProgressView().controlSize(.small) }
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
        if index < photos.count {
            Image(uiImage: photos[index])
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    Button {
                        photos.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .padding(4)
                    }
                    .accessibilityLabel("Remove photo \(index + 1)")
                }
        } else if index == photos.count, remainingSlots > 0 {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: remainingSlots,
                matching: .images,
                photoLibrary: .shared()
            ) {
                EmptyPhotoSlot(showsPlus: true)
            }
        } else {
            EmptyPhotoSlot(showsPlus: false)
        }
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
