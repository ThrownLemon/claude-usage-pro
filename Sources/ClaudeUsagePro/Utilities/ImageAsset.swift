import AppKit
import SwiftUI

/// Helper for loading images from raw (uncompiled) asset catalogs in Swift Package Manager.
/// SPM doesn't compile .xcassets into .car files like Xcode does, so we need to
/// manually read the Contents.json and load the PNG files directly.
enum ImageAsset {
    /// Load an NSImage from the bundle's Assets.xcassets by imageset name.
    /// - Parameter name: The name of the imageset (e.g., "ocean_bg_dark")
    /// - Returns: The loaded NSImage, or nil if not found
    static func loadImage(named name: String) -> NSImage? {
        guard let resourcePath = Bundle.module.resourcePath else {
            Log.error(Log.Category.app, "Bundle.module.resourcePath is nil")
            return nil
        }

        let imagesetPath = "\(resourcePath)/Assets.xcassets/\(name).imageset"

        // Try to read Contents.json to get the actual filename
        let contentsPath = "\(imagesetPath)/Contents.json"
        if let contentsData = FileManager.default.contents(atPath: contentsPath),
            let contents = try? JSONDecoder().decode(ImagesetContents.self, from: contentsData),
            let imageInfo = contents.images.first(where: { $0.filename != nil }),
            let filename = imageInfo.filename
        {
            let imagePath = "\(imagesetPath)/\(filename)"
            if let image = NSImage(contentsOfFile: imagePath) {
                Log.debug(Log.Category.app, "Loaded image from: \(imagePath)")
                return image
            }
        }

        // Fallback: try common extensions directly
        for ext in ["png", "jpg", "jpeg"] {
            let imagePath = "\(imagesetPath)/\(name).\(ext)"
            if let image = NSImage(contentsOfFile: imagePath) {
                Log.debug(Log.Category.app, "Loaded image (fallback) from: \(imagePath)")
                return image
            }
        }

        Log.warning(Log.Category.app, "Failed to load image: \(name)")
        return nil
    }
}

/// SwiftUI Image view that loads from raw asset catalog
struct AssetImage: View {
    let name: String
    let contentMode: ContentMode

    @State private var nsImage: NSImage?

    init(_ name: String, contentMode: ContentMode = .fill) {
        self.name = name
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let nsImage = nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                // Invisible placeholder while loading
                Color.clear
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: name) {
            loadImage()
        }
    }

    private func loadImage() {
        // Load synchronously since it's from local bundle
        nsImage = ImageAsset.loadImage(named: name)
    }
}

// MARK: - JSON Decoding Structs

private struct ImagesetContents: Codable {
    let images: [ImageInfo]
    let info: CatalogInfo

    struct ImageInfo: Codable {
        let filename: String?
        let idiom: String?
        let scale: String?
    }

    struct CatalogInfo: Codable {
        let author: String
        let version: Int
    }
}
