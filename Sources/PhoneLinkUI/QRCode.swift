// QRCode — generate a QR image from a pairing payload using CoreImage (no
// third-party dependency).
//
// SPDX-License-Identifier: MIT

#if canImport(CoreImage) && canImport(AppKit)
import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

public enum QRCode {
    /// Render `string` as a crisp QR NSImage. `scale` enlarges the raw modules.
    public static func image(from string: String, scale: CGFloat = 10) -> NSImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
#endif
