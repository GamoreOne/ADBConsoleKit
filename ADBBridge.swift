import Foundation
import Combine

// Центральный Swift-слой приложения.
// Все вызовы ADB выполняются в фоне: adb connect / dumpsys / install могут занимать секунды,
// и на главном потоке они бы «замораживали» интерфейс.
final class ADBBridge: ObservableObject {
    // Один общий экземпляр используется всеми экранами приложения.
    static let shared = ADBBridge()

    // Низкоуровневый bridge, который вызывает adb-mobile.
    private let objc = ADBBridgeObjC.shared()

    // Состояние подключения и признак «идёт команда» для SwiftUI (меняются только на главном потоке).
    @Published private(set) var connected = false
    @Published private(set) var busy = false

    // Максимум символов, которые показываем в UI. dumpsys batterystats может отдать мегабайты текста.
    static let displayLimit = 60_000

    // Обрезает слишком длинный вывод, чтобы SwiftUI не тормозил.
    static func clip(_ text: String, limit: Int = ADBBridge.displayLimit) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        return head + "\n… [вывод обрезан: показано \(limit) из \(text.count) символов]"
    }

    // Выполняет блокирующий вызов adb-mobile в фоне и возвращает результат на вызывающий поток.
    private func perform(_ work: @escaping () -> String) async -> String {
        await MainActor.run { self.busy = true }
        let result = await Task.detached(priority: .userInitiated) { work() }.value
        await MainActor.run { self.busy = false }
        return ADBBridge.clip(result)
    }

    // Подключается к Android-устройству по IP:port.
    func connect(host: String, port: String) async -> String {
        let objc = self.objc
        let result = await perform { objc.connect(host, port: port) }
        let lower = result.lowercased()

        // Успех — стандартный ответ ADB. Проверяем ошибки первыми: «failed to connect»
        // не должен считаться подключением.
        let failed = lower.contains("failed") || lower.contains("cannot") ||
                     lower.contains("unable") || lower.contains("error") ||
                     lower.contains("refused") || lower.contains("timed out")
        let ok = lower.contains("connected to") || lower.contains("already connected to")

        await MainActor.run {
            if ok && !failed {
                self.connected = true
            } else if failed {
                self.connected = false
            }
        }
        return result
    }

    // Разрывает ADB-соединение с указанным устройством.
    func disconnect(host: String, port: String) async -> String {
        let objc = self.objc
        let result = await perform { objc.disconnect(host, port: port) }
        await MainActor.run { self.connected = false }
        return result
    }

    // Выполняет именно adb shell <command>.
    func shell(_ command: String) async -> String {
        let objc = self.objc
        return await perform { objc.shell(command) }
    }

    // Выполняет обычную ADB-команду без префикса shell.
    func run(_ command: String) async -> String {
        let objc = self.objc
        return await perform { objc.run(command) }
    }

    // Проверяет `adb devices` и обновляет индикатор подключения.
    func refreshStatus() async -> String {
        let result = await run("devices")
        let hasDevice = result
            .split(whereSeparator: { $0.isNewline })
            .dropFirst() // строка "List of devices attached"
            .contains { line in
                let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
                return parts.last == "device"
            }
        await MainActor.run { self.connected = hasDevice }
        return result
    }

    // Копирует выбранный APK из Files в sandbox приложения и устанавливает его.
    func installAPK(from url: URL) async -> String {
        let objc = self.objc
        return await perform {
            let fm = FileManager.default

            // Documents/Imports — постоянная папка внутри sandbox приложения.
            let imports = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Imports", isDirectory: true)

            do {
                try fm.createDirectory(at: imports, withIntermediateDirectories: true)

                // Files выдаёт security-scoped URL; доступ нужен только на время копирования.
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let safeName = url.lastPathComponent.isEmpty
                    ? "selected.apk"
                    : url.lastPathComponent

                let destination = imports.appendingPathComponent(safeName)

                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }

                try fm.copyItem(at: url, to: destination)

                // Передаём локальный путь в adb-mobile.
                return objc.installAPK(destination.path)
            } catch {
                return "APK copy error: \(error.localizedDescription)"
            }
        }
    }
}
