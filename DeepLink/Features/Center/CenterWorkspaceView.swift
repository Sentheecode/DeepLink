import SwiftUI

enum CenterHistoryFilter: String, CaseIterable {
    case all = "全部"
    case voice = "语音"
    case photo = "图像"
    case memo = "文字"
}

struct CenterWorkspaceView: View {
    @Binding var defaultMode: CenterTabMode
    @State private var filter: CenterHistoryFilter = .all

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("记录类型", selection: $filter) {
                    ForEach(CenterHistoryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    Section("快速记录") {
                        HStack(spacing: 12) {
                            modeButton(.voice, "语音", "waveform")
                            modeButton(.camera, "拍照", "camera")
                            modeButton(.keyboard, "文字", "keyboard")
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                    }

                    if filter == .all || filter == .voice {
                        Section("语音") {
                            NavigationLink("查看语音记录", destination: VoiceHistoryView())
                        }
                    }
                    if filter == .all || filter == .photo {
                        Section("图像") {
                            NavigationLink("查看识别与拍照记录", destination: PhotoHistoryView())
                        }
                    }
                    if filter == .all || filter == .memo {
                        Section("文字") {
                            NavigationLink("查看备忘录与指派", destination: CenterMemoModeView())
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Center")
        }
    }

    private func modeButton(_ mode: CenterTabMode, _ title: String, _ icon: String) -> some View {
        Button {
            defaultMode = mode
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(defaultMode == mode ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(defaultMode == mode ? Color.primary : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
