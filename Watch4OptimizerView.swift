import SwiftUI

// Экран консервативной оптимизации Galaxy Watch 4.
// Команды здесь обратимые: отключение пакета можно отменить кнопкой «Включить».
struct Watch4OptimizerView: View {
    @ObservedObject var adb: ADBBridge
    let append: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let candidates: [(String, String)] = [
        ("com.google.android.wearable.assistant", "Google Assistant"),
        ("com.google.android.apps.walletnfcrel", "Google Wallet"),
        ("com.google.android.tts", "Google Text-to-Speech")
    ]

    @State private var output = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    infoCard

                    Button {
                        runShell("dumpsys battery")
                    } label: {
                        Label("Проверить батарею", systemImage: "battery.100percent")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        runShell("pm list packages")
                    } label: {
                        Label("Показать пакеты", systemImage: "shippingbox")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    ForEach(candidates, id: \.0) { package, title in
                        packageCard(package: package, title: title)
                    }

                    if !output.isEmpty {
                        Text(output)
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
            .navigationTitle("Оптимизация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Консервативный профиль", systemImage: "shield.checkered")
                .font(.headline)
            Text("Здесь нет отключения Google Play Services, Health Services, Bluetooth или Wear OS Core. Каждая операция обратима.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func packageCard(package: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(package)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button("Отключить") {
                    runPackageCommand("pm disable-user --user 0 \(package)")
                }
                .buttonStyle(.borderedProminent)

                Button("Включить") {
                    runPackageCommand("pm enable --user 0 \(package)")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func runPackageCommand(_ command: String) {
        runShell(command)
    }

    // Выполняет adb shell в фоне, затем показывает результат здесь и в общей консоли.
    private func runShell(_ command: String) {
        Task { @MainActor in
            let result = await adb.shell(command)
            output = result
            append("$ adb shell \(command)\n\(result)")
        }
    }
}
