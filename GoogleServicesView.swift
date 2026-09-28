import SwiftUI

// Отдельный экран для Google-компонентов.
// Он вынесен отдельно, чтобы агрессивные изменения не смешивались с обычным optimizer.
struct GoogleServicesView: View {
    @ObservedObject var adb: ADBBridge
    let append: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var result = ""
    @State private var working = false

    // Пакет + человекочитаемое назначение.
    private let services: [(String, String, Bool)] = [
        ("com.google.android.wearable.assistant", "Google Assistant", false),
        ("com.google.android.apps.walletnfcrel", "Google Wallet", false),
        ("com.google.android.tts", "Google Text-to-Speech", false),
        ("com.google.android.gsf", "Google Services Framework", true)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Предупреждение о том, что GSF отличается от обычного optional bloat.
                    warningCard

                    ForEach(services, id: \.0) { item in
                        serviceCard(package: item.0, title: item.1, aggressive: item.2)
                    }

                    // Позволяет проверить реальное наличие пакетов на конкретной прошивке.
                    Button {
                        checkPackages()
                    } label: {
                        Label("Проверить Google-пакеты", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if !result.isEmpty {
                        Text(result)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
                .disabled(adb.busy)
            }
            .navigationTitle("Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    // Карточка с предупреждением о потенциальных последствиях GSF.
    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Важно", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)

            Text("Google Services Framework отключается отдельно. Это может повлиять на Google-аккаунт, синхронизацию, уведомления и связанные функции Wear OS.")
                .font(.footnote)

            Text("Если нужен максимум автономности — отключай GSF только после теста обычного профиля.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Строит одну Google-карточку.
    private func serviceCard(package: String, title: String, aggressive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: aggressive ? "bolt.trianglebadge.exclamationmark" : "g.circle")
                    .font(.title2)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)

                    Text(package)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if aggressive {
                Text("АГРЕССИВНО")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Отключить") {
                    setEnabled(false, package: package, title: title)
                }
                .buttonStyle(.borderedProminent)

                Button("Включить") {
                    setEnabled(true, package: package, title: title)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // Выполняет обратимое отключение или включение пакета.
    private func setEnabled(_ enabled: Bool, package: String, title: String) {
        let command = enabled
            ? "pm enable --user 0 \(package)"
            : "pm disable-user --user 0 \(package)"

        Task { @MainActor in
            working = true
            let output = await adb.shell(command)
            result = output
            append("$ adb shell \(command)\n\(output)")
            working = false
        }
    }

    // Показывает только реально установленные Google-пакеты.
    private func checkPackages() {
        Task { @MainActor in
            working = true
            let allPackages = await adb.shell("pm list packages")
            let googlePackages = allPackages
                .split(whereSeparator: { $0.isNewline })
                .map(String.init)
                .filter { $0.localizedCaseInsensitiveContains("google") }
                .joined(separator: "\n")

            result = googlePackages.isEmpty ? "Google-пакеты не найдены." : googlePackages
            append("$ adb shell pm list packages\n\(result)")
            working = false
        }
    }
}
