import SwiftUI

struct DatabasePickerView: View {
    let profile: ConnectionProfile
    var session: RedisSession
    var store: ConnectionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName)
                        .font(.title2.weight(.semibold))
                    Text(session.handshake?.summary ?? "已连接 · \(profile.endpointText)")
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("断开", role: .destructive) {
                    store.disconnect(profile)
                }
            }

            Text("选择数据库")
                .font(.headline)

            Text("连接配置未指定数据库，请选择要浏览的 DB。")
                .foregroundStyle(.secondary)

            if session.isLoadingDatabases && session.databaseOptions.isEmpty {
                ProgressView("正在加载数据库列表…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(session.databaseOptions) { option in
                    Button {
                        Task { await session.selectDatabase(option.index) }
                    } label: {
                        HStack {
                            Text("DB \(option.index)")
                                .foregroundStyle(.primary)
                            Spacer()
                            if let keyCount = option.keyCount {
                                Text("\(keyCount.formatted()) keys")
                                    .foregroundStyle(.secondary)
                                    .font(.callout.monospacedDigit())
                            } else {
                                Text("—")
                                    .foregroundStyle(.tertiary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("选择数据库")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await session.refreshDatabaseOptions() }
                }
                .disabled(session.isLoadingDatabases)
            }
        }
        .task(id: session.isConnected) {
            if session.needsDatabaseSelection, session.databaseOptions.isEmpty {
                await session.refreshDatabaseOptions()
            }
        }
    }
}
