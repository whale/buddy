import SwiftUI
import UIKit
import AVFoundation

// MARK: - QRScannerView (P3)
// A camera QR scanner for pairing. Wraps AVCaptureSession + AVCaptureMetadataOutput (.qr).
// The iOS Simulator has NO camera, so session setup fails there — we detect that and show a
// clear "camera unavailable" state. The manual-paste path in Settings always works, so pairing
// is testable without hardware; the camera scan itself is only exercisable on a real device.
struct QRScannerView: View {
    var onScan: (String) -> Void
    var onCancel: () -> Void

    @State private var unavailable = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if unavailable {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.system(size: 34)).foregroundStyle(.white.opacity(0.7))
                    Text("Camera unavailable")
                        .font(.geist(18, .medium)).foregroundStyle(.white)
                    Text("Use “Enter details manually” in Settings to pair on the simulator.")
                        .font(.geist(14, .regular)).foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
            } else {
                CameraPreview(onScan: onScan, onUnavailable: { unavailable = true })
                    .ignoresSafeArea()
                // Framing hint
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)
                VStack {
                    Spacer()
                    Text("Point at the QR code on your Mac")
                        .font(.geist(15, .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 60)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { onCancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30)).foregroundStyle(.white.opacity(0.9))
                            .padding(20)
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - AVFoundation preview + metadata capture
private struct CameraPreview: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.coordinator = context.coordinator
        vc.onUnavailable = onUnavailable
        return vc
    }
    func updateUIViewController(_ vc: ScannerVC, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        private var didScan = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didScan,
                  let obj = objects.first as? AVMetadataMachineReadableCodeObject,
                  obj.type == .qr, let s = obj.stringValue else { return }
            didScan = true
            DispatchQueue.main.async { self.onScan(s) }
        }
    }
}

private final class ScannerVC: UIViewController {
    var coordinator: CameraPreview.Coordinator?
    var onUnavailable: (() -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { onUnavailable?(); return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { onUnavailable?(); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }
}
