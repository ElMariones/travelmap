import SwiftUI

/// Loads one visit photo from Supabase Storage.
///
/// The bucket is private, so the stored value is an object path that has to be swapped
/// for a short-lived signed URL before an image view can load it.
struct StoragePhotoView: View {
    let path: String

    @State private var url: URL?
    @State private var didFail = false

    var body: some View {
        Group {
            if didFail {
                placeholder(systemImage: "photo.badge.exclamationmark")
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(systemImage: "photo.badge.exclamationmark")
                    default:
                        placeholder(systemImage: nil)
                    }
                }
            } else {
                placeholder(systemImage: nil)
            }
        }
        .clipped()
        .task(id: path) {
            do {
                url = try await VisitsService().signedURL(for: path)
            } catch {
                didFail = true
            }
        }
    }

    private func placeholder(systemImage: String?) -> some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }
}
