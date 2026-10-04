import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Companion

/// The pairing sheet: shows a QR code the companion app scans to connect over
/// Wi-Fi (or USB). The QR is generated with CoreImage — no third-party library.
struct PairingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Pair your phone")
                .font(.title2).bold()

            if model.companionConnected {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56)).foregroundStyle(.green)
                    Text("Phone connected").font(.title3)
                }
                .frame(width: 320, height: 320)
            } else if let code = model.pairingCode {
                qr(for: code.encoded())
                VStack(spacing: 4) {
                    Text("Open the mac-phone-link app on your phone and scan this code.")
                        .font(.callout).multilineTextAlignment(.center)
                    Text("\(code.host):\(code.port)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 360)
            } else {
                ProgressView("Starting companion server…")
                    .frame(width: 320, height: 320)
            }

            HStack {
                if !model.companionConnected {
                    Button("Copy link") {
                        if let s = model.pairingCode?.encoded() {
                            let pb = NSPasteboard.general
                            pb.clearContents(); pb.setString(s, forType: .string)
                        }
                    }
                }
                Spacer()
                Button(model.companionConnected ? "Done" : "Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 360)
        }
        .padding(24)
    }

    @ViewBuilder private func qr(for string: String) -> some View {
        if let image = Self.qrImage(from: string) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 320, height: 320)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Text("Couldn't generate QR code").frame(width: 320, height: 320)
        }
    }

    /// Render a QR code bitmap for `string` using CoreImage.
    static func qrImage(from string: String, scale: CGFloat = 12) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: transformed.extent.width,
                                                 height: transformed.extent.height))
    }
}
