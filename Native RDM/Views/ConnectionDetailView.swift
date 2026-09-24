import SwiftUI

struct ConnectionDetailView: View {
    let profile: ConnectionProfile
    var session: RedisSession
    var store: ConnectionStore
    @State private var commandText = "PING"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            infoGrid
            actionBar
            if session.isConnected {
                commandBar
            }
            responsePane
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(profile.displayName)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cylinder.split.1x2")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.title2.weight(.semibold))
                Text(statusText)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            Button("编辑") { store.beginEdit(profile) }
        }
    }

    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            row("主机", profile.host)
            row("端口", String(profile.port))
            row("数据库", String(profile.database))
            row("用户名", profile.username.isEmpty ? "—" : profile.username)
            row("TLS", profile.useTLS ? (profile.verifyTLSCertificate ? "开启（校验证书）" : "开启（不校验证书）") : "关闭")
            row("超时", "\(Int(profile.connectTimeout)) 秒")
        }
        .font(.body)
    }

    private var actionBar: some View {
        HStack {
            switch session.status {
            case .connecting:
                ProgressView("正在连接…")
                Button("取消") { store.disconnect(profile) }
            case .connected:
                Button("断开", role: .destructive) { store.disconnect(profile) }
                Button("PING") {
                    Task { await session.run(["PING"]) }
                }
                Button("INFO") {
                    Task { await session.run(["INFO", "server"]) }
                }
            default:
                Button("连接") { store.connect(profile) }
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
            if let latency = session.lastLatency {
                Text(latencyText(latency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var commandBar: some View {
        HStack {
            TextField("命令，例如 PING 或 GET mykey", text: $commandText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { sendCommand() }
            Button("执行") { sendCommand() }
                .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var responsePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("响应")
                .font(.headline)
            ScrollView {
                Text(session.lastResponse.isEmpty ? "连接成功后可执行 PING / INFO 或自定义命令。" : session.lastResponse)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var statusText: String {
        switch session.status {
        case .disconnected:
            return "未连接 · \(profile.endpointText)"
        case .connecting:
            return "正在连接 \(profile.endpointText)…"
        case .connected:
            return session.handshake?.summary ?? "已连接 · \(profile.endpointText)"
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .connected: .green
        case .failed: .red
        case .connecting: .orange
        case .disconnected: .secondary
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
        }
    }

    private func sendCommand() {
        let tokens = RedisCommandLine.tokenize(commandText)
        Task { await session.run(tokens) }
    }

    private func latencyText(_ duration: Duration) -> String {
        let millis = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        if millis < 1 {
            return String(format: "%.2f ms", millis)
        }
        return String(format: "%.1f ms", millis)
    }
}
