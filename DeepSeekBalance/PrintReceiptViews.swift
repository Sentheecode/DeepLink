import SwiftUI
import WidgetKit
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Foreground print transition

struct PrintAnimationView: View {
    let trigger: UUID?
    let summary: UserSummary?

    @State private var islandWidth: CGFloat = 126
    @State private var islandHeight: CGFloat = 37
    @State private var paperOffset: CGFloat = -330
    @State private var paperOpacity = 0.0
    @State private var slotOpacity = 0.0
    @State private var isVisible = false
    @State private var isPreviewVisible = false
    @State private var previewScale = 0.42
    @State private var previewOffset: CGFloat = -250
    @State private var backdropOpacity = 0.0
    @State private var controlsOpacity = 0.0
    @State private var shareImage: BillShareImage?

    private let paperHeight: CGFloat = 560
    private let slotHeight: CGFloat = 2
    private let slotOverlap: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let expandedWidth = min(proxy.size.width - 34, 380)
            let paperWidth = floor(min(proxy.size.width - 72, 320))
            let slotY = floor(islandHeight / 2)

            ZStack(alignment: .top) {
                if isVisible {
                    island
                        .frame(width: islandWidth, height: islandHeight)
                        .zIndex(2)

                    paperOutput(width: paperWidth, slotY: slotY)
                        .zIndex(3)
                }

                if isPreviewVisible {
                    Color.black.opacity(backdropOpacity)
                        .contentShape(Rectangle())
                        .onTapGesture { }
                        .zIndex(4)

                    preview(width: floor(min(proxy.size.width - 32, 390)))
                        .scaleEffect(previewScale, anchor: .top)
                        .offset(y: previewOffset)
                        .zIndex(5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 11)
            .task(id: trigger) {
                guard trigger != nil else { return }
                await runSequence(expandedWidth: expandedWidth)
            }
        }
    }

    private var island: some View {
        RoundedRectangle(cornerRadius: islandHeight / 2, style: .continuous)
            .fill(.black)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }

    private func paperOutput(width: CGFloat, slotY: CGFloat) -> some View {
        ZStack(alignment: .top) {
            receipt
                .frame(width: width, height: paperHeight)
                .offset(y: paperOffset - slotY)
                .opacity(paperOpacity)
        }
        .frame(width: width, height: paperHeight + 90, alignment: .top)
        .clipped(antialiased: false)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(white: 0.78))
                .frame(width: width, height: slotHeight)
                .offset(y: -slotOverlap)
                .opacity(slotOpacity)
        }
        .offset(y: slotY)
    }

    private var receipt: some View {
        BillReceiptView(summary: summary)
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 12)
    }

    private func preview(width: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("账单预览")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: closePreview) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .accessibilityLabel("关闭账单")
            }

            ScrollView(.vertical) {
                BillReceiptView(summary: summary)
                    .frame(width: width)
            }
            .scrollIndicators(.hidden)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 22, y: 12)

            HStack(spacing: 10) {
                if let shareImage {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview("DeepSeek API 账单", image: Image(uiImage: shareImage.preview))
                    ) {
                        actionButton("分享图片", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    UIPasteboard.general.string = shareText
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    actionButton("复制摘要", systemImage: "doc.on.doc")
                }

                Button {
                    closePreview()
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        await runSequence(expandedWidth: min(UIScreen.main.bounds.width - 34, 380))
                    }
                } label: {
                    actionButton("重新打印", systemImage: "printer")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 48)
        .padding(.bottom, 28)
        .opacity(controlsOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func actionButton(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    @MainActor
    private func runSequence(expandedWidth: CGFloat) async {
        reset()
        isVisible = true

        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            islandWidth = expandedWidth
        }
        guard await pause(0.38) else { return }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
            islandHeight = 74
            slotOpacity = 1
        }
        guard await pause(0.35) else { return }

        paperOpacity = 1
        withAnimation(.linear(duration: 2.15)) {
            // Expanded island is 74pt high; its center line is the exact paper origin.
            paperOffset = 36
        }
        guard await pause(2.3) else { return }

        presentPreview()
    }

    @MainActor
    private func reset() {
        islandWidth = 126
        islandHeight = 37
        paperOffset = -330
        paperOpacity = 0
        slotOpacity = 0
        isPreviewVisible = false
        previewScale = 0.42
        previewOffset = -250
        backdropOpacity = 0
        controlsOpacity = 0
        shareImage = nil
    }

    private func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    @MainActor
    private func presentPreview() {
        shareImage = renderShareImage()
        isPreviewVisible = true

        withAnimation(.easeInOut(duration: 0.42)) {
            backdropOpacity = 0.72
            previewScale = 1
            previewOffset = 0
            controlsOpacity = 1
            paperOpacity = 0
            slotOpacity = 0
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.84).delay(0.12)) {
            islandHeight = 37
            islandWidth = 126
        }
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            isVisible = false
        }
    }

    @MainActor
    private func closePreview() {
        withAnimation(.easeInOut(duration: 0.28)) {
            previewScale = 0.88
            previewOffset = 60
            backdropOpacity = 0
            controlsOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            isPreviewVisible = false
            shareImage = nil
        }
    }

    @MainActor
    private func renderShareImage() -> BillShareImage? {
        let content = BillReceiptView(summary: summary)
            .frame(width: 390, height: paperHeight)
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage,
              let data = image.pngData() else { return nil }
        return BillShareImage(data: data, preview: image)
    }

    private var shareText: String {
        let wallet = summary?.normalWallets.first
        return """
        DeepSeek API 账单
        可用余额：\(wallet?.balance ?? "--") \(wallet?.currency ?? "")
        本月 Token：\(summary?.monthlyTokenUsage ?? "--")
        本月消费：\(summary?.monthlyCosts.first?.amount ?? "--")
        """
    }
}

struct BillReceiptView: View {
    let summary: UserSummary?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 34))
                .foregroundStyle(Color(red: 0.64, green: 0.12, blue: 0.15))

            Text("DEEPSEEK API")
                .font(.system(.title3, design: .serif).weight(.bold))
            Text("MONTHLY USAGE RECEIPT")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            receiptDivider
            row("可用余额", formattedBalance)
            row("本月 Token", compactNumber(summary?.monthlyTokenUsage))
            row("本月消费", formattedCost)
            row("预计可用 Token", compactNumber(summary?.totalAvailableTokenEstimation))
            receiptDivider

            VStack(spacing: 9) {
                ForEach(summary?.monthlyCosts ?? [], id: \.currency) { cost in
                    row("\(cost.currency) 消费", cost.amount)
                }
            }

            Spacer(minLength: 32)
            receiptDivider
            Text(Date().formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("THANK YOU")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.64, green: 0.12, blue: 0.15))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, minHeight: 560)
        .background(Color(red: 0.98, green: 0.97, blue: 0.92))
    }

    private var receiptDivider: some View {
        HStack(spacing: 6) {
            Rectangle().frame(height: 1)
            Image(systemName: "diamond.fill").font(.system(size: 5))
            Rectangle().frame(height: 1)
        }
        .foregroundStyle(Color(red: 0.64, green: 0.12, blue: 0.15).opacity(0.55))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced().weight(.semibold))
        }
    }

    private var formattedBalance: String {
        guard let wallet = summary?.normalWallets.first else { return "--" }
        guard let value = Double(wallet.balance) else { return wallet.balance }
        return wallet.currency == "CNY"
            ? "¥\(String(format: "%.2f", value))"
            : String(format: "%.2f %@", value, wallet.currency)
    }

    private var formattedCost: String {
        guard let amount = summary?.monthlyCosts.first?.amount,
              let value = Double(amount) else { return "--" }
        return "¥\(String(format: "%.2f", value))"
    }

    private func compactNumber(_ value: String?) -> String {
        guard let value, let number = Double(value) else { return value ?? "--" }
        if number >= 1_000_000 { return String(format: "%.2fM", number / 1_000_000) }
        if number >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return String(format: "%.0f", number)
    }
}

struct BillShareImage: Transferable {
    let data: Data
    let preview: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.data
        }
        .suggestedFileName("DeepSeek-API-Receipt.png")
    }
}
