import SwiftUI
import AVFoundation
import Speech
import Vision

// MARK: - Center Tab Default Gate

struct CenterDefaultGate: View {
    let defaultMode: CenterTabMode
    @State private var showCamera = false
    @State private var showVoiceHistory = false
    @State private var photoHistoryId = UUID()

    var body: some View {
        Group {
            switch defaultMode {
            case .voice:
                NavigationStack {
                    VoiceRecordingView(showHistory: $showVoiceHistory)
                        .navigationDestination(isPresented: $showVoiceHistory) {
                            VoiceHistoryView()
                        }
                }
            case .camera:
                NavigationStack {
                    PhotoHistoryView()
                        .id(photoHistoryId)
                }
                .onAppear { showCamera = true }
                .fullScreenCover(isPresented: $showCamera) {
                    DirectCameraView()
                }
                .onChange(of: showCamera) { _, showing in
                    if !showing { photoHistoryId = UUID() }
                }
            case .keyboard:
                NavigationStack {
                    CenterMemoModeView()
                }
            }
        }
    }
}

// MARK: - Direct Camera (AVFoundation full-screen, no chrome)

struct DirectCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var capturedImage: UIImage?

    var body: some View {
        ZStack {
            CameraPreview(capturedImage: $capturedImage)
                .ignoresSafeArea()

            // Bottom shutter button
            VStack {
                Spacer()
                Button {
                    takePhoto()
                } label: {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().fill(Color.white).frame(width: 62, height: 62))
                        .shadow(color: .black.opacity(0.3), radius: 8)
                }
                .padding(.bottom, 50)
            }

            // Top close
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                Spacer()
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .dismissCamera)) { _ in
            dismiss()
        }
    }

    private func takePhoto() {
        NotificationCenter.default.post(name: .capturePhoto, object: nil)
    }
}

extension Notification.Name {
    static let capturePhoto = Notification.Name("capturePhoto")
}

struct CameraPreview: UIViewRepresentable {
    @Binding var capturedImage: UIImage?

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.session = context.coordinator.setupSession()
        context.coordinator.startSession()
        return view
    }

    func updateUIView(_: CameraPreviewView, context: Context) {}

    func makeCoordinator() -> CameraCoordinator {
        CameraCoordinator(capturedImage: $capturedImage)
    }
}

class CameraPreviewView: UIView {
    var session: AVCaptureSession? {
        didSet {
            guard let session else { return }
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            previewLayer = layer
            self.layer.addSublayer(layer)
        }
    }
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

@MainActor
class CameraCoordinator: NSObject, AVCapturePhotoCaptureDelegate {
    @Binding var capturedImage: UIImage?
    private var session: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?

    init(capturedImage: Binding<UIImage?>) {
        _capturedImage = capturedImage
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(capture), name: .capturePhoto, object: nil)
    }

    func setupSession() -> AVCaptureSession {
        let session = AVCaptureSession()
        self.session = session
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return session
        }

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCapturePhotoOutput()
        self.photoOutput = output
        if session.canAddOutput(output) { session.addOutput(output) }

        return session
    }

    func startSession() {
        Task { [weak self] in
            self?.session?.startRunning()
        }
    }

    @objc func capture() {
        let settings = AVCapturePhotoSettings()
        photoOutput?.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        // Run OCR on a background thread
        var recognizedText = ""
        if let cgImage = image.cgImage {
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }

        Task { @MainActor [weak self] in
            if let jpegData = image.jpegData(compressionQuality: 0.6) {
                PhotoHistoryStore.add(imageData: jpegData, recognizedText: recognizedText)
            }
            self?.capturedImage = image
            // Send to default agent
            Task { await AgentDispatcher.sendToDefaultAgent(title: "拍照", content: "拍摄了一张照片。\(recognizedText.isEmpty ? "" : "识别文字: \(recognizedText)")") }
            // Dismiss after saving
            NotificationCenter.default.post(name: .dismissCamera, object: nil)
        }
    }
}

extension Notification.Name {
    static let dismissCamera = Notification.Name("dismissCamera")
}

// MARK: - Center Hub Launcher

struct CenterHubView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showCamera = false
    @State private var showVoice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Voice
                    Button {
                        showVoice = true
                    } label: {
                        CenterTile(icon: "waveform", title: "语音", color: .blue)
                    }
                    .buttonStyle(.plain)

                    // Photo
                    Button {
                        showCamera = true
                    } label: {
                        CenterTile(icon: "camera.fill", title: "拍照", color: .green)
                    }
                    .buttonStyle(.plain)

                    // Keyboard
                    NavigationLink(destination: CenterMemoModeView()) {
                        CenterTile(icon: "keyboard.fill", title: "键盘", color: .orange)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.vertical, 6)

                    // History buttons (subtle, smaller)
                    NavigationLink(destination: VoiceHistoryView()) {
                        CenterHistoryTile(icon: "waveform.circle.fill", title: "语音历史", color: .purple)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: PhotoHistoryView()) {
                        CenterHistoryTile(icon: "camera.circle.fill", title: "拍照历史", color: .mint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CenterPhotoModeView()
        }
        .fullScreenCover(isPresented: $showVoice) {
            VoiceFullscreenWrapper(isPresented: $showVoice)
        }
    }
}

private struct CenterTile: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct CenterHistoryTile: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Voice Fullscreen Wrapper (fixes 完成 → history navigation)

private struct VoiceFullscreenWrapper: View {
    @Binding var isPresented: Bool
    @State private var showVoiceHistory = false

    var body: some View {
        NavigationStack {
            VoiceRecordingView(showHistory: $showVoiceHistory)
                .navigationDestination(isPresented: $showVoiceHistory) {
                    VoiceHistoryView()
                }
        }
    }
}

// MARK: - Voice Recording (minimal redesign)

struct VoiceRecordingView: View {
    @Binding var showHistory: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var transcribedText = ""
    @State private var alertMessage = ""
    @State private var showPermissionAlert = false
    @State private var isRecording = true

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine: AVAudioEngine?
    @State private var audioLevels: [CGFloat] = Array(repeating: 4, count: 24)
    @State private var audioTimer: Timer?
    @State private var audioRecorderFile: AVAudioFile?
    @State private var lastAudioFileName: String?
    private var audioFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "voice_\(UUID().uuidString.prefix(8)).caf"
        return dir.appendingPathComponent(filename)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar — just close
                HStack {
                    Button {
                        let audioName = stopRecording()
                        let text = transcribedText.trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty {
                            VoiceHistoryStore.add(text, audioFilename: audioName)
                            UIPasteboard.general.string = text
                            Task { await AgentDispatcher.sendToDefaultAgent(title: "语音", content: text) }
                        }
                        dismiss()
                        showHistory = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("语音").font(.headline).foregroundColor(.primary)
                    Spacer()
                    // Equally spaced placeholder for centering
                    Color.clear.frame(width: 28, height: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)

                Spacer()

                // Waveform — centered, subtle
                VStack(spacing: 20) {
                    HStack(spacing: 3) {
                        ForEach(0..<audioLevels.count, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.blue.opacity(0.6))
                                .frame(width: 3, height: audioLevels[i])
                                .animation(.easeInOut(duration: 0.25), value: audioLevels[i])
                        }
                    }
                    .frame(height: 50)

                    if transcribedText.isEmpty {
                        Text(isRecording ? "正在聆听" : "处理中")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Transcription
                if !transcribedText.isEmpty {
                    ScrollView {
                        Text(transcribedText)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .frame(maxHeight: 200)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                Spacer()

                // Single "完成" button
                Button {
                    let audioName = stopRecording()
                    let text = transcribedText.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        VoiceHistoryStore.add(text, audioFilename: audioName)
                        UIPasteboard.general.string = text
                        Task { await AgentDispatcher.sendToDefaultAgent(title: "语音", content: text) }
                    }
                    showHistory = true
                } label: {
                    Text("完成")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .alert(alertMessage, isPresented: $showPermissionAlert) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("取消", role: .cancel) { dismiss() }
        }
        .onAppear {
            requestPermissionsAndStart()
            startAudioLevelSimulation()
        }
        .onDisappear { audioTimer?.invalidate() }
    }

    private func startAudioLevelSimulation() {
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            guard isRecording else { return }
            audioLevels = audioLevels.map { _ in
                CGFloat(4 + Int.random(in: 0...40))
            }
        }
    }

    private func requestPermissionsAndStart() {
        AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
            DispatchQueue.main.async {
                guard micGranted else {
                    alertMessage = "请在设置中允许麦克风权限。"
                    showPermissionAlert = true
                    return
                }
                SFSpeechRecognizer.requestAuthorization { status in
                    DispatchQueue.main.async {
                        guard status == .authorized else {
                            alertMessage = "请在设置中允许语音识别权限。"
                            showPermissionAlert = true
                            return
                        }
                        startRecognition()
                    }
                }
            }
        }
    }

    private func startRecognition() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            alertMessage = "语音识别不可用。"
            showPermissionAlert = true
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let engine = AVAudioEngine()
            audioEngine = engine

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            // Create audio file for saving the recording
            let fileURL = audioFileURL
            lastAudioFileName = fileURL.lastPathComponent
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            audioRecorderFile = audioFile

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
                // Write to audio file
                try? audioFile.write(from: buffer)
                // Real audio level
                if let channelData = buffer.floatChannelData {
                    let channelDataValue = channelData.pointee
                    let frameLength = Int(buffer.frameLength)
                    var sum: Float = 0
                    for i in 0..<min(frameLength, 1024) {
                        sum += abs(channelDataValue[i])
                    }
                    let avg = sum / Float(min(frameLength, 1024))
                    let level = max(4, min(50, CGFloat(avg * 80)))
                    DispatchQueue.main.async {
                        guard isRecording else { return }
                        audioLevels = audioLevels.map { _ in level + CGFloat.random(in: -8...8) }
                    }
                }
            }

            engine.prepare()
            try engine.start()

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                DispatchQueue.main.async {
                    if let r = result { transcribedText = r.bestTranscription.formattedString }
                    if error != nil { stopEngine() }
                }
            }
        } catch {
            alertMessage = "启动失败: \(error.localizedDescription)"
            showPermissionAlert = true
        }
    }

    private func stopRecording() -> String? {
        guard isRecording else { return nil }
        isRecording = false
        audioTimer?.invalidate()
        audioTimer = nil
        recognitionTask?.cancel()
        stopEngine()
        let filename = lastAudioFileName
        lastAudioFileName = nil
        guard VoiceAudioFile.isPlayable(filename: filename) else {
            if let filename {
                try? FileManager.default.removeItem(at: VoiceAudioFile.documentsDirectory.appendingPathComponent(filename))
            }
            return nil
        }
        return filename
    }

    private func stopEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        audioRecorderFile = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

// MARK: - Full-screen Photo Mode (Vision)

struct CenterPhotoModeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var capturedImage: UIImage?
    @State private var includeLocation = false
    @State private var showCamera = false
    @State private var recognizedText = ""
    @State private var isRecognizing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("拍照")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("位置", isOn: $includeLocation)
                        .toggleStyle(.button)
                        .tint(.green)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 12)

                Spacer()

                if let image = capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(16)

                    if !recognizedText.isEmpty {
                        ScrollView {
                            Text(recognizedText)
                                .font(.body)
                                .foregroundColor(.white)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                        }
                        .frame(maxHeight: 120)
                    }

                    HStack(spacing: 24) {
                        Button {
                            capturedImage = nil
                            recognizedText = ""
                            showCamera = true
                        } label: {
                            Label("重拍", systemImage: "arrow.counterclockwise")
                                .foregroundColor(.white)
                        }
                        Button {
                            recognizeText(in: image)
                        } label: {
                            if isRecognizing {
                                ProgressView().tint(.white)
                            } else {
                                Label("识别", systemImage: "eye.fill")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                } else {
                    Button {
                        showCamera = true
                    } label: {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 48))
                            Text("点击拍照")
                                .font(.title3)
                        }
                        .foregroundColor(.white)
                        .frame(width: 200, height: 200)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                }

                Spacer()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(capturedImage: $capturedImage)
        }
        .onChange(of: capturedImage) { _ in
            recognizedText = ""
        }
        .onAppear {
            if capturedImage == nil {
                showCamera = true
            }
        }
    }

    private func recognizeText(in image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        isRecognizing = true

        let request = VNRecognizeTextRequest { request, error in
            DispatchQueue.main.async {
                isRecognizing = false
                if let error = error {
                    recognizedText = "识别失败: \(error.localizedDescription)"
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                recognizedText = text.isEmpty ? "未识别到文字" : text
                if !text.isEmpty {
                    // Save compressed JPEG data to PhotoHistoryStore
                    if let jpegData = image.jpegData(compressionQuality: 0.6),
                       jpegData.count <= 500 * 1024 {
                        PhotoHistoryStore.add(imageData: jpegData, recognizedText: text)
                    } else if let jpegData = image.jpegData(compressionQuality: 0.3),
                              jpegData.count <= 500 * 1024 {
                        PhotoHistoryStore.add(imageData: jpegData, recognizedText: text)
                    }
                }
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}

// MARK: - Camera Capture Wrapper

struct CameraCaptureView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        init(_ p: CameraCaptureView) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.capturedImage = image }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Voice History

struct VoiceHistoryItem: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
    let audioFilename: String?

    init(text: String, audioFilename: String? = nil) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.audioFilename = audioFilename
    }
}

struct VoiceHistoryStore {
    static let key = "voiceHistory"
    static func load() -> [VoiceHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([VoiceHistoryItem].self, from: data) else {
            return []
        }
        return items
    }
    static func save(_ items: [VoiceHistoryItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    static func add(_ text: String, audioFilename: String? = nil) {
        var items = load()
        items.insert(VoiceHistoryItem(text: text, audioFilename: audioFilename), at: 0)
        save(items)
    }
    static func delete(_ id: UUID) {
        var items = load()
        items.removeAll { $0.id == id }
        save(items)
    }
}

// MARK: - Photo History

struct PhotoHistoryItem: Codable, Identifiable {
    let id: UUID
    let imageData: Data
    let recognizedText: String
    let date: Date

    init(imageData: Data, recognizedText: String) {
        self.id = UUID()
        self.imageData = imageData
        self.recognizedText = recognizedText
        self.date = Date()
    }
}

struct PhotoHistoryStore {
    static let key = "photoHistory"
    static func load() -> [PhotoHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([PhotoHistoryItem].self, from: data) else {
            return []
        }
        return items
    }
    static func save(_ items: [PhotoHistoryItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    static func add(imageData: Data, recognizedText: String) {
        var items = load()
        items.insert(PhotoHistoryItem(imageData: imageData, recognizedText: recognizedText), at: 0)
        save(items)
    }
    static func delete(_ id: UUID) {
        var items = load()
        items.removeAll { $0.id == id }
        save(items)
    }
}

// MARK: - Voice History View

struct VoiceHistoryView: View {
    @State private var items: [VoiceHistoryItem] = []
    @State private var searchText = ""
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioPlayerDelegate: AudioPlayerDelegate?
    @State private var playingItemID: UUID?
    @State private var playbackError = ""

    private var filteredItems: [VoiceHistoryItem] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "暂无历史记录" : "无搜索结果",
                    systemImage: "waveform",
                    description: Text("语音识别的内容会自动保存在这里。")
                )
            } else {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.text)
                                    .font(.body)
                                    .lineLimit(3)
                                Text(item.date.formatted())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if VoiceAudioFile.isPlayable(filename: item.audioFilename) {
                                Spacer()
                                Button {
                                    playAudio(item: item)
                                } label: {
                                    Image(systemName: playingItemID == item.id ? "stop.circle.fill" : "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) {
                            deleteItem(item)
                        }
                    }
                }
            }
        }
        .navigationTitle("语音历史")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索语音记录")
        .onAppear { items = VoiceHistoryStore.load() }
        .onDisappear {
            audioPlayer?.stop()
            audioPlayerDelegate = nil
        }
        .alert("无法播放录音", isPresented: Binding(
            get: { !playbackError.isEmpty },
            set: { if !$0 { playbackError = "" } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(playbackError)
        }
    }

    private func playAudio(item: VoiceHistoryItem) {
        if playingItemID == item.id {
            audioPlayer?.stop()
            playingItemID = nil
            return
        }

        guard let filename = item.audioFilename else {
            print("Playback: no audio filename for item \(item.id)")
            return
        }
        let url = VoiceAudioFile.documentsDirectory.appendingPathComponent(filename)

        guard VoiceAudioFile.isPlayable(filename: filename) else {
            playbackError = "录音文件已经丢失或不完整。"
            return
        }

        // Print file info for debugging
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attrs?[.size] as? Int ?? 0
        print("Playing audio: \(url.lastPathComponent), size: \(fileSize) bytes")

        do {
            // Reset audio session: deactivate then set playback mode
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let delegate = AudioPlayerDelegate {
                DispatchQueue.main.async { playingItemID = nil }
            }
            audioPlayerDelegate = delegate
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = delegate
            audioPlayer?.prepareToPlay()
            guard audioPlayer?.play() == true else {
                playbackError = "系统无法启动这个录音文件。"
                return
            }
            playingItemID = item.id
            print("Playback started successfully")
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private func deleteItem(_ item: VoiceHistoryItem) {
        // Delete audio file if exists
        if let filename = item.audioFilename {
            let url = VoiceAudioFile.documentsDirectory.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
        VoiceHistoryStore.delete(item.id)
        items = VoiceHistoryStore.load()
    }
}

// Helper for audio player completion callback
private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully flag: Bool) { onFinish() }
}

// MARK: - Photo History View

struct PhotoHistoryView: View {
    @State private var items: [PhotoHistoryItem] = []
    @State private var searchText = ""

    private var filteredItems: [PhotoHistoryItem] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.recognizedText.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "暂无历史记录" : "无搜索结果",
                    systemImage: "camera.fill",
                    description: Text("拍照识别的内容会自动保存在这里。")
                )
            } else {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(destination: PhotoDetailView(item: item)) {
                        HStack(spacing: 12) {
                            if let image = UIImage(data: item.imageData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.recognizedText.isEmpty ? "无识别文字" : item.recognizedText)
                                    .font(.body)
                                    .foregroundColor(item.recognizedText.isEmpty ? .secondary : .primary)
                                    .lineLimit(2)
                                Text(item.date.formatted())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) {
                            PhotoHistoryStore.delete(item.id)
                            items = PhotoHistoryStore.load()
                        }
                    }
                }
            }
        }
        .navigationTitle("拍照历史")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索拍照记录")
        .onAppear { items = PhotoHistoryStore.load() }
    }
}

// MARK: - Photo Detail View

struct PhotoDetailView: View {
    let item: PhotoHistoryItem

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Full image
                if let image = UIImage(data: item.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 8)
                        .padding(.horizontal, 8)
                }

                // Date
                HStack {
                    Image(systemName: "clock").font(.caption).foregroundColor(.secondary)
                    Text(item.date.formatted())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)

                // Recognized text
                if !item.recognizedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "text.viewfinder").font(.caption).foregroundColor(.blue)
                            Text("识别文字").font(.subheadline.weight(.semibold))
                        }
                        Text(item.recognizedText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 16)
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.circle").font(.caption).foregroundColor(.orange)
                        Text("未识别到文字").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("照片详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
