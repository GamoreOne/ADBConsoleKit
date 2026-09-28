import SwiftUI

// Диагностика батареи не меняет настройки устройства.
// Она только запускает стандартные dumpsys-команды и показывает результат.
struct BatteryDiagnosticsView: View {
    @ObservedObject var adb: ADBBridge
    let append: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var output = ""

    private let checks: [(String, String, String)] = [
        ("Состояние батареи", "battery.100percent", "dumpsys battery"),
        ("BatteryStats", "chart.bar.doc.horizontal", "dumpsys batterystats"),
        ("Alarms", "alarm", "dumpsys alarm"),
        ("Jobs", "clock.badge.checkmark", "dumpsys jobscheduler"),
        ("Process stats", "cpu", "dumpsys procstats")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(checks, id: \.0) { title, icon, command in
                        Button {
                            run(command)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .frame(width: 28)
                                Text(title)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        run("dumpsys batterystats --charged")
                    } label: {
                        Label("BatteryStats с момента зарядки", systemImage: "bolt.batteryblock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        run("dumpsys batterystats --reset")
                    } label: {
                        Label("Сбросить BatteryStats", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if !output.isEmpty {
                        Text(output)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.black)
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
                .disabled(adb.busy)
            }
            .navigationTitle("Батарея")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    // Выполняет adb shell в фоне, затем показывает результат здесь и в общей консоли.
    private func run(_ command: String) {
        Task { @MainActor in
            let result = await adb.shell(command)
            output = result
            append("$ adb shell \(command)\n\(result)")
        }
    }
}
