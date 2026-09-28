import SwiftUI
import UniformTypeIdentifiers

// Главный экран приложения.
// Визуально построен как dashboard: устройство сверху, статус и крупные карточки действий.
struct ContentView: View {
    @StateObject private var adb = ADBBridge.shared

    @AppStorage("host") private var host = ""
    @AppStorage("port") private var port = "5555"

    @State private var command = ""
    @State private var output = ""
    @State private var picker = false
    @State private var showingWatch = false
    @State private var showingGoogle = false
    @State private var showingBattery = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Мягкий фон в стиле современных smart-home приложений.
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        deviceCard
                        quickActions
                        consoleCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Watch Control")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingWatch) {
                Watch4OptimizerView(adb: adb, append: append)
            }
            .sheet(isPresented: $showingGoogle) {
                GoogleServicesView(adb: adb, append: append)
            }
            .sheet(isPresented: $showingBattery) {
                BatteryDiagnosticsView(adb: adb, append: append)
            }
            .fileImporter(
                isPresented: $picker,
                allowedContentTypes: apkTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }

                    guard url.pathExtension.lowercased() == "apk" else {
                        append("ERROR: выбранный файл не APK")
                        return
                    }

                    Task { @MainActor in
                        append("$ adb install -r \(url.lastPathComponent)")
                        append(await adb.installAPK(from: url))
                    }

                case .failure(let error):
                    append("File picker: \(error.localizedDescription)")
                }
            }
        }
    }

    // Большая карточка подключаемого устройства.
    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Galaxy Watch 4")
                        .font(.title2.bold())

                    Text(adb.connected ? "ADB подключён" : "ADB не подключён")
                        .font(.subheadline)
                        .foregroundStyle(adb.connected ? .green : .secondary)
                }

                Spacer()

                Image(systemName: "applewatch")
                    .font(.system(size: 42))
                    .symbolRenderingMode(.hierarchical)
            }

            HStack(spacing: 8) {
                TextField("IP", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)

                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
                    .frame(width: 78)
                    .textFieldStyle(.roundedBorder)

                Button(adb.connected ? "Отключить" : "Подключить") {
                    Task { @MainActor in
                        if adb.connected {
                            append(await adb.disconnect(host: host, port: port))
                        } else {
                            append("$ adb connect \(host):\(port)")
                            append(await adb.connect(host: host, port: port))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(adb.busy)
            }

            Button {
                Task { @MainActor in
                    append("$ adb devices")
                    append(await adb.refreshStatus())
                }
            } label: {
                Label("Проверить соединение", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(adb.busy)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }

    // Четыре крупные функции, как в smart-home интерфейсе.
    private var quickActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                actionCard(
                    title: "Оптимизация",
                    subtitle: "Процессы и автозапуск",
                    icon: "bolt.fill"
                ) {
                    showingWatch = true
                }

                actionCard(
                    title: "Google",
                    subtitle: "Сервисы и GSF",
                    icon: "g.circle.fill"
                ) {
                    showingGoogle = true
                }
            }

            HStack(spacing: 12) {
                actionCard(
                    title: "Батарея",
                    subtitle: "Wakelock / jobs / alarms",
                    icon: "battery.100percent"
                ) {
                    showingBattery = true
                }

                actionCard(
                    title: "APK",
                    subtitle: "Установить файл",
                    icon: "square.and.arrow.down"
                ) {
                    picker = true
                }
            }
        }
    }

    // Универсальная карточка быстрого действия.
    private func actionCard(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    // Нижняя консоль остаётся доступной для ручного ADB.
    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ADB Console")
                    .font(.headline)

                if adb.busy {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Очистить") {
                    output = ""
                }
                .font(.caption)
            }

            ScrollView {
                Text(output.isEmpty ? "Вывод ADB появится здесь…" : output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 150, maxHeight: 280)
            .padding()
            .background(Color.black)
            .foregroundStyle(.green)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(alignment: .bottom) {
                TextField("shell-команда или «adb …»", text: $command, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button("Run") {
                    let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !c.isEmpty else { return }
                    command = ""

                    Task { @MainActor in
                        // Если строка начинается с "adb " — выполняем обычную ADB-команду
                        // (например: adb pair 192.168.1.5:37000 123456, adb devices, adb tcpip 5555).
                        // Иначе это команда для `adb shell`.
                        if c.lowercased().hasPrefix("adb ") {
                            let rest = String(c.dropFirst(4))
                            append("$ adb \(rest)")
                            append(await adb.run(rest))
                        } else {
                            append("$ adb shell \(c)")
                            append(await adb.shell(c))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(adb.busy)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    // Единая функция добавления строк в консоль.
    private func append(_ text: String) {
        guard !text.isEmpty else { return }

        if output.isEmpty {
            output = text
        } else {
            output += "\n" + text
        }

        // Консоль не должна расти бесконечно: оставляем последние ~120 000 символов.
        let maxLength = 120_000
        if output.count > maxLength {
            output = "… [начало вывода удалено]\n" + String(output.suffix(maxLength))
        }
    }

    // Файловый выбор: .apk (если система знает тип) и любой файл как запасной вариант.
    private var apkTypes: [UTType] {
        var types: [UTType] = [.data]
        if let apk = UTType(filenameExtension: "apk") {
            types.insert(apk, at: 0)
        }
        return types
    }
}
