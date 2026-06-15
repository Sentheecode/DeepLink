import SwiftUI

struct WorkflowBoardView: View {
    let devices: [AgentDevice]
    @State private var workflows = WorkflowStore.load()
    @State private var showComposer = false

    var body: some View {
        List {
            if workflows.isEmpty {
                ContentUnavailableView(
                    "还没有工作流",
                    systemImage: "point.3.filled.connected.trianglepath.dotted",
                    description: Text("把采集、审查和分析交给不同 Agent，按顺序协作。")
                )
            }
            ForEach(workflows) { workflow in
                Section(workflow.name) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !workflow.goal.isEmpty {
                            Text(workflow.goal).font(.subheadline)
                        }
                        HStack {
                            Label(workflow.state.title, systemImage: "repeat")
                            Spacer()
                            Text("\(workflow.currentIteration)/\(workflow.maxIterations) 轮")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.secondary)
                                .frame(width: 24, height: 24).background(.thinMaterial).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.headline)
                                Text("\(step.deviceName) / \(step.agentName)").font(.caption).foregroundStyle(.secondary)
                                if !step.instructions.isEmpty {
                                    Text(step.instructions).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                if let reviewer = step.reviewerAgentName {
                                    Label("由 \(reviewer) 审查", systemImage: "checkmark.seal")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if step.requiresHumanApproval {
                                    Label("需要人工确认", systemImage: "person.crop.circle.badge.checkmark")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Text(step.state.title).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("工作流")
        .toolbar {
            Button { showComposer = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showComposer) {
            WorkflowComposerView(devices: devices) { workflow in
                workflows.insert(workflow, at: 0)
                WorkflowStore.save(workflows)
            }
        }
    }
}

private struct WorkflowComposerView: View {
    let devices: [AgentDevice]
    let onSave: (AgentWorkflow) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var goal = ""
    @State private var successCriteria = ""
    @State private var maxIterations = 3
    @State private var steps: [AgentWorkflowStep] = []
    @State private var selectedAgentID = ""
    @State private var reviewerAgentID = ""
    @State private var stepTitle = ""
    @State private var instructions = ""
    @State private var requiresHumanApproval = false

    private var targets: [AgentAssignmentTarget] {
        devices.flatMap { device in device.agents.map { AgentAssignmentTarget(agent: $0, deviceName: device.name) } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Loop 目标") {
                    TextField("例如：产出可用的数据分析报告", text: $name)
                    TextField("目标描述", text: $goal, axis: .vertical)
                    TextField("成功条件", text: $successCriteria, axis: .vertical)
                    Stepper("最多循环 \(maxIterations) 轮", value: $maxIterations, in: 1...20)
                }
                Section("新增步骤") {
                    Picker("执行 Agent", selection: $selectedAgentID) {
                        Text("选择 Agent").tag("")
                        ForEach(targets) { Text("\($0.deviceName) / \($0.title)").tag($0.id) }
                    }
                    Picker("审查 Agent", selection: $reviewerAgentID) {
                        Text("不单独审查").tag("")
                        ForEach(targets) { Text("\($0.deviceName) / \($0.title)").tag($0.id) }
                    }
                    TextField("步骤名称", text: $stepTitle)
                    TextField("任务说明", text: $instructions, axis: .vertical)
                    Toggle("完成后需要人工确认", isOn: $requiresHumanApproval)
                    Button("加入步骤", action: addStep)
                        .disabled(selectedAgentID.isEmpty || stepTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("执行顺序") {
                    ForEach(steps) { step in
                        VStack(alignment: .leading) {
                            Text(step.title)
                            Text("\(step.deviceName) / \(step.agentName)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .navigationTitle("新建工作流")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(AgentWorkflow(
                            name: name,
                            goal: goal,
                            successCriteria: successCriteria,
                            maxIterations: maxIterations,
                            steps: steps
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || steps.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
    }

    private func addStep() {
        guard let target = targets.first(where: { $0.id == selectedAgentID }) else { return }
        let reviewer = targets.first(where: { $0.id == reviewerAgentID })
        steps.append(AgentWorkflowStep(
            title: stepTitle,
            instructions: instructions,
            agentID: target.id,
            agentName: target.title,
            deviceName: target.deviceName,
            reviewerAgentID: reviewer?.id,
            reviewerAgentName: reviewer?.title,
            requiresHumanApproval: requiresHumanApproval
        ))
        stepTitle = ""
        instructions = ""
        reviewerAgentID = ""
        requiresHumanApproval = false
    }
}
