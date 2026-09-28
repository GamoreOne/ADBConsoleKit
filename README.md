# ADBConsoleKit — Galaxy Watch 4 Control

iPhone-приложение: ADB по TCP к Galaxy Watch 4 / Android, диагностические команды.

Сборка **только** через GitHub Actions (`macos-15`, Xcode 16.4). Подпись Apple в CI не нужна.
Артефакт: `ADBConsoleKit-unsigned.ipa`. Дальше подписываешь сам.

Инструкция с телефона: `GITHUB_SETUP.txt`.

Что починено в этой версии:
- падение за ~3 минуты на `git submodule --recursive` с `android.googlesource.com`;
- lz4/zstd/brotli/protobuf качаются с GitHub, не с googlesource;
- ретраи и зеркала для vendor android-tools;
- заголовок `adb_public.h` (upstream переименовал `adb_puiblic.h`);
- обязательный callback `adb_connect_status_updated` для линкера;
- unsigned `xcodebuild` с `-destination generic/platform=iOS`;
- хвост лога в Summary, если снова упадёт.
