import AppKit
import ImageIO

final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, NSImage>()
    private let failures = NSCache<NSString, NSNumber>()
    private let queue = DispatchQueue(label: "app.goodsticky.thumbnails", qos: .utility)
    private let lock = NSLock()
    private var pending: [NSString: [(NSImage?) -> Void]] = [:]
    init() { cache.countLimit = 24; cache.totalCostLimit = 4 * 1024 * 1024; failures.countLimit = 24 }
    func load(_ url: URL, pixels: Int, completion: @escaping (NSImage?) -> Void) {
        load(url, fitting: CGSize(width: pixels, height: pixels), completion: completion)
    }
    /// Decodes only as many pixels as an aspect-fit preview in `box` (device pixels) shows.
    func load(_ url: URL, fitting box: CGSize, completion: @escaping (NSImage?) -> Void) {
        let box = CGSize(width: max(1, box.width.rounded(.up)), height: max(1, box.height.rounded(.up)))
        let key = (url.path + "-\(Int(box.width))x\(Int(box.height))") as NSString
        lock.lock()
        if let image = cache.object(forKey: key) {
            lock.unlock(); DispatchQueue.main.async { completion(image) }; return
        }
        if failures.object(forKey: key) != nil { lock.unlock(); DispatchQueue.main.async { completion(nil) }; return }
        if pending[key] != nil { pending[key]?.append(completion); lock.unlock(); return }
        pending[key] = [completion]; lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            var result: NSImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: Self.maxPixel(source, fitting: box), kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                self.cache.setObject(result!, forKey: key, cost: cg.bytesPerRow * cg.height)
            } else { self.failures.setObject(true, forKey: key) }
            self.lock.lock(); let callbacks = self.pending.removeValue(forKey: key) ?? []; self.lock.unlock()
            DispatchQueue.main.async { for callback in callbacks { callback(result) } }
        }
    }
    /// Longest side, in pixels, of the image once aspect-fit into `box` (never upscaled).
    static func maxPixel(_ source: CGImageSource, fitting box: CGSize) -> Int {
        let fallback = Int(max(box.width, box.height))
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, width > 0, height > 0 else { return fallback }
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 { swap(&width, &height) }
        let scale = min(1, min(Double(box.width) / width, Double(box.height) / height))
        return max(1, Int((max(width, height) * scale).rounded(.up)))
    }
}
