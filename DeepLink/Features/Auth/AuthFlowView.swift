import SwiftUI

// MARK: - Auth Flow Container

struct AuthFlowView: View {
    let onLoginSuccess: () -> Void

    var body: some View {
        NavigationStack {
            AuthLandingView(onLoginSuccess: onLoginSuccess)
        }
    }
}

// MARK: - Landing (User List)

struct AuthLandingView: View {
    let onLoginSuccess: () -> Void
    @State private var savedUsers: [String] = UserDefaults.standard.savedUserNames

    private let brandBlue = Color(red: 0.11, green: 0.42, blue: 0.87)
    private let brandDark = Color(red: 0.04, green: 0.2, blue: 0.5)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                VStack(spacing: 16) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(colors: [brandBlue, brandDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("DeepLink")
                        .font(.largeTitle.weight(.bold))
                    Text("管理你的 DeepSeek 余额与 Agent")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)

                if !savedUsers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("历史用户")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)

                        ForEach(savedUsers, id: \.self) { username in
                            NavigationLink {
                                UserLoginView(username: username, onLoginSuccess: onLoginSuccess)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "person.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(brandBlue)
                                    Text(username)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 24)
                }

                VStack(spacing: 12) {
                    NavigationLink {
                        AuthLoginView(onLoginSuccess: onLoginSuccess)
                    } label: {
                        Text(savedUsers.isEmpty ? "登录" : "其他用户登录")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(brandBlue)
                    .controlSize(.large)

                    NavigationLink {
                        AuthRegisterView(onLoginSuccess: onLoginSuccess)
                    } label: {
                        Text("注册新账户")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(brandBlue)
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: UIScreen.main.bounds.height)
        }
        .onAppear {
            savedUsers = UserDefaults.standard.savedUserNames
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - User Login (Quick login for saved user)

struct UserLoginView: View {
    let username: String
    let onLoginSuccess: () -> Void

    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @FocusState private var isPasswordFocused: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color(red: 0.11, green: 0.42, blue: 0.87))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(username)
                            .font(.body.weight(.medium))
                        Text("点击「切换账户」返回")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                SecureField("密码", text: $password)
                    .focused($isPasswordFocused)
                    .submitLabel(.done)
                    .onSubmit(performLogin)
            } header: {
                Text("请输入密码")
            }

            Section {
                Button(action: performLogin) {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("登录")
                        }
                        Spacer()
                    }
                }
                .disabled(isLoading || password.isEmpty)
                .listRowBackground(
                    (!isLoading && !password.isEmpty)
                    ? Color(red: 0.11, green: 0.42, blue: 0.87)
                    : Color(.systemGray5)
                )
                .foregroundStyle(.white)
                .font(.body.weight(.semibold))
            }

            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.callout)
                }
            }

            Section {
                Button("切换账户") {
                    dismiss()
                }
            }
        }
        .navigationTitle("登录")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isPasswordFocused = true
        }
    }

    private func performLogin() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = ""
        Task {
            do {
                let client = RemoteBrokerClient()
                try await client.login(username: username, password: password)
                saveUserName(username)
                UserDefaults.standard.hasCompletedLogin = true
                await MainActor.run { onLoginSuccess() }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func saveUserName(_ name: String) {
        var users = UserDefaults.standard.savedUserNames
        if !users.contains(name) {
            users.append(name)
            UserDefaults.standard.savedUserNames = users
        }
    }
}

// MARK: - Login

struct AuthLoginView: View {
    let onLoginSuccess: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    enum Field { case username, password }

    var body: some View {
        Form {
            Section {
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                SecureField("密码", text: $password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit(performLogin)
            } header: {
                Text("DeepLink 账户")
            } footer: {
                Text("登录后可管理 Agent 设备与模型凭证。")
            }

            Section {
                Button(action: performLogin) {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("登录")
                        }
                        Spacer()
                    }
                }
                .disabled(isLoading || username.isEmpty || password.isEmpty)
                .listRowBackground(
                    (!isLoading && !username.isEmpty && !password.isEmpty)
                    ? Color(red: 0.11, green: 0.42, blue: 0.87)
                    : Color(.systemGray5)
                )
                .foregroundStyle(.white)
                .font(.body.weight(.semibold))
            }

            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.callout)
                }
            }

            Section {
                NavigationLink("还没有账户？注册") {
                    AuthRegisterView(onLoginSuccess: onLoginSuccess)
                }
            }
        }
        .navigationTitle("登录")
        .onAppear { focusedField = .username }
    }

    private func performLogin() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = ""
        Task {
            do {
                let client = RemoteBrokerClient()
                try await client.login(username: username, password: password)
                saveUserName(username)
                UserDefaults.standard.hasCompletedLogin = true
                await MainActor.run { onLoginSuccess() }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func saveUserName(_ name: String) {
        var users = UserDefaults.standard.savedUserNames
        if !users.contains(name) {
            users.append(name)
            UserDefaults.standard.savedUserNames = users
        }
    }
}

// MARK: - Register

struct AuthRegisterView: View {
    let onLoginSuccess: () -> Void

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    enum Field { case username, email, password, confirm }

    private var usernameError: String? {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.count < 2 { return "用户名至少 2 个字符" }
        return nil
    }

    private var emailError: String? {
        if email.isEmpty { return nil }
        if !email.contains("@") || !email.contains(".") { return "邮箱格式不正确" }
        return nil
    }

    private var passwordError: String? {
        if password.isEmpty { return nil }
        if password.count < 8 { return "密码至少 8 个字符" }
        return nil
    }

    private var confirmError: String? {
        if confirmPassword.isEmpty { return nil }
        if confirmPassword != password { return "两次密码不一致" }
        return nil
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.isEmpty
            && password.count >= 8
            && confirmPassword == password
    }

    var body: some View {
        Form {
            Section {
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }
                if let error = usernameError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                TextField("邮箱", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                if let error = emailError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                SecureField("密码", text: $password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirm }
                if let error = passwordError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                SecureField("确认密码", text: $confirmPassword)
                    .focused($focusedField, equals: .confirm)
                    .submitLabel(.done)
                    .onSubmit(performRegister)
                if let error = confirmError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            } header: {
                Text("创建账户")
            }

            Section {
                Button(action: performRegister) {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("注册") }
                        Spacer()
                    }
                }
                .disabled(isLoading || !canSubmit)
                .listRowBackground(
                    (!isLoading && canSubmit)
                    ? Color(red: 0.11, green: 0.42, blue: 0.87)
                    : Color(.systemGray5)
                )
                .foregroundStyle(.white)
                .font(.body.weight(.semibold))
            }

            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.callout)
                }
            }

            Section {
                NavigationLink("已有账户？登录") {
                    AuthLoginView(onLoginSuccess: onLoginSuccess)
                }
            }
        }
        .navigationTitle("注册")
        .onAppear { focusedField = .username }
    }

    private func performRegister() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = ""
        Task {
            do {
                let client = RemoteBrokerClient()
                try await client.register(username: username, email: email, password: password)
                saveUserName(username)
                UserDefaults.standard.hasCompletedLogin = true
                await MainActor.run { onLoginSuccess() }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func saveUserName(_ name: String) {
        var users = UserDefaults.standard.savedUserNames
        if !users.contains(name) {
            users.append(name)
            UserDefaults.standard.savedUserNames = users
        }
    }
}

// MARK: - First Launch Setup

struct FirstLaunchSetupView: View {
    let onComplete: () -> Void

    @State private var selectedMode: AgentConnectionMode = .local
    @State private var hermesURL = UserDefaults.standard.string(forKey: "hermesURL") ?? "http://localhost:8642"
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("欢迎使用 DeepLink")
                .font(.title2.weight(.bold))

            Text("请选择 Agent 连接方式")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Button {
                    selectedMode = .local
                } label: {
                    HStack {
                        Image(systemName: "house.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("本地模式")
                                .font(.body.weight(.medium))
                            Text("连接本地运行的 Hermes 服务")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedMode == .local {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    selectedMode = .broker
                } label: {
                    HStack {
                        Image(systemName: "cloud.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("云端模式")
                                .font(.body.weight(.medium))
                            Text("通过 Broker 云端管理 Agent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedMode == .broker {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            if selectedMode == .local {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hermes 地址")
                        .font(.subheadline.weight(.medium))
                    TextField("http://localhost:8642", text: $hermesURL)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 24)
                }

                // API Key field (local mode only)
                if selectedMode == .local {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key（可选）")
                            .font(.subheadline.weight(.medium))
                        TextField("API Key（可选）", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 24)
                }

            Spacer()

            Button(action: complete) {
                Text("完成")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func complete() {
        UserDefaults.standard.set(selectedMode.rawValue, forKey: BrokerDefaults.connectionModeKey)
        if selectedMode == .local {
            UserDefaults.standard.set(hermesURL, forKey: "hermesURL")
            if !apiKey.isEmpty {
                try? KeychainCredentialStore().saveToken(apiKey, for: .hermesKey)
            } else {
                try? KeychainCredentialStore().deleteToken(for: .hermesKey)
            }
            Task {
                await HermesAPI.shared.configure(baseURL: hermesURL, apiKey: apiKey)
            }
        }
        UserDefaults.standard.hasCompletedSetup = true
        onComplete()
    }
}
