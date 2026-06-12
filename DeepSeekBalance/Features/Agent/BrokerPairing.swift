import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

struct BrokerQRCodeView: View {
    let value: String
    var size: CGFloat = 220

    var body: some View {
        if let image = Self.makeImage(value) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("配对二维码")
        }
    }

    private static func makeImage(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct BrokerQRScannerView: UIViewControllerRepresentable {
    let onScan: (URL) -> Void
    let onError: (String) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

    final class Coordinator: NSObject, QRScannerDelegate {
        private let onScan: (URL) -> Void
        private let onError: (String) -> Void
        private let onCancel: () -> Void

        init(onScan: @escaping (URL) -> Void, onError: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onError = onError
            self.onCancel = onCancel
        }

        func scannerDidScan(_ url: URL) { onScan(url) }
        func scannerDidFail(_ message: String) { onError(message) }
        func scannerDidCancel() { onCancel() }
    }
}

protocol QRScannerDelegate: AnyObject {
    func scannerDidScan(_ url: URL)
    func scannerDidFail(_ message: String)
    func scannerDidCancel()
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRScannerDelegate?
    private let session = AVCaptureSession()
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
        configureCloseButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            delegate?.scannerDidFail("无法使用相机")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            delegate?.scannerDidFail("无法启动二维码识别")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        let guide = UIView()
        guide.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        guide.layer.borderWidth = 2
        guide.layer.cornerRadius = 24
        guide.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guide)
        NSLayoutConstraint.activate([
            guide.widthAnchor.constraint(equalToConstant: 250),
            guide.heightAnchor.constraint(equalTo: guide.widthAnchor),
            guide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guide.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func configureCloseButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 22
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeScanner), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
    }

    @objc private func closeScanner() {
        session.stopRunning()
        delegate?.scannerDidCancel()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              let url = URL(string: value) else { return }
        didScan = true
        session.stopRunning()
        delegate?.scannerDidScan(url)
    }
}
