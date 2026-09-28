#import "ADBBridge.h"

// Upstream с 2024-11 переименовал заголовок: adb_puiblic.h → adb_public.h.
#if __has_include("adb_public.h")
#include "adb_public.h"
#elif __has_include("adb_puiblic.h")
#include "adb_puiblic.h"
#else
#error "adb-mobile public header not found (adb_public.h)"
#endif

#include <stdlib.h>
#include <string.h>

// Обязательный callback из libadb: линкер ищет этот символ в приложении.
void adb_connect_status_updated(const char *serial, const char *status) {
    NSLog(@"[ADB] %s: %s", serial ? serial : "?", status ? status : "?");
}

@implementation ADBBridgeObjC

+ (instancetype)shared {
    static ADBBridgeObjC *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ADBBridgeObjC alloc] init];
    });
    return instance;
}

// Один раз настраивает ADB home (там лежат ключи) и отдельный порт локального ADB-сервера.
// Строки копируются через strdup: библиотека может хранить указатель, а UTF8String
// у автоосвобождаемой NSString после выхода из autoreleasepool становится недействительным.
- (void)prepare {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *paths =
            NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                 NSUserDomainMask,
                                                 YES);
        NSString *documentHome = paths.firstObject ?: NSTemporaryDirectory();
        adb_set_server_port("15037");
        adb_set_home(strdup(documentHome.UTF8String));
    });
}

// Универсальный исполнитель argv для adb-mobile.
// Вызовы сериализуются: adb-mobile не рассчитан на параллельные команды.
- (NSString *)runArgc:(int)argc argv:(const char * _Nonnull [])argv {
    @synchronized (self) {
        [self prepare];

        char *output = NULL;
        size_t outputSize = 0;

        int ret = adb_commandline_porting(&output, &outputSize, argc, argv);

        NSString *result = @"";
        if (output != NULL && outputSize > 0) {
            result = [[NSString alloc] initWithBytes:output
                                              length:outputSize
                                            encoding:NSUTF8StringEncoding];
            if (result == nil) {
                result = [[NSString alloc] initWithBytes:output
                                                  length:outputSize
                                                encoding:NSISOLatin1StringEncoding] ?: @"";
            }
        }

        if (ret != 0) {
            if (result.length == 0) {
                return [NSString stringWithFormat:@"ADB error: %d", ret];
            }
            return [NSString stringWithFormat:@"%@\nADB exit code: %d", result, ret];
        }

        return result;
    }
}

static NSString *ADBTrim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)connect:(NSString *)host port:(NSString *)port {
    NSString *cleanHost = ADBTrim(host);
    NSString *cleanPort = ADBTrim(port);

    if (cleanHost.length == 0) {
        return @"ADB error: IP/host is empty";
    }
    if (cleanPort.length == 0) {
        cleanPort = @"5555";
    }

    NSString *endpoint = [NSString stringWithFormat:@"%@:%@", cleanHost, cleanPort];

    const char *argv[] = {"connect", endpoint.UTF8String};
    return [self runArgc:2 argv:argv];
}

- (NSString *)disconnect:(NSString *)host port:(NSString *)port {
    NSString *cleanHost = ADBTrim(host);
    NSString *cleanPort = ADBTrim(port);

    if (cleanHost.length == 0) {
        const char *argv[] = {"disconnect"};
        return [self runArgc:1 argv:argv];
    }

    if (cleanPort.length == 0) {
        cleanPort = @"5555";
    }

    NSString *endpoint = [NSString stringWithFormat:@"%@:%@", cleanHost, cleanPort];

    const char *argv[] = {"disconnect", endpoint.UTF8String};
    return [self runArgc:2 argv:argv];
}

- (NSString *)shell:(NSString *)command {
    NSString *cleanCommand = ADBTrim(command);

    if (cleanCommand.length == 0) {
        return @"ADB error: shell command is empty";
    }

    const char *argv[] = {"shell", cleanCommand.UTF8String};
    return [self runArgc:2 argv:argv];
}

- (NSString *)run:(NSString *)command {
    NSString *cleanCommand = ADBTrim(command);

    if (cleanCommand.length == 0) {
        return @"ADB error: command is empty";
    }

    NSMutableArray<NSString *> *storage = [NSMutableArray array];
    for (NSString *part in [cleanCommand componentsSeparatedByString:@" "]) {
        if (part.length > 0) {
            [storage addObject:part];
        }
    }

    if (storage.count == 0) {
        return @"ADB error: command is empty";
    }

    int argc = (int)storage.count;
    const char **argv = calloc((size_t)argc, sizeof(char *));
    if (argv == NULL) {
        return @"ADB error: memory allocation failed";
    }

    for (int i = 0; i < argc; i++) {
        argv[i] = storage[(NSUInteger)i].UTF8String;
    }

    NSString *result = [self runArgc:argc argv:argv];
    free(argv);
    return result;
}

- (NSString *)installAPK:(NSString *)path {
    if (path.length == 0) {
        return @"ADB error: APK path is empty";
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return [NSString stringWithFormat:@"ADB error: APK not found: %@", path];
    }

    const char *argv[] = {"install", "-r", path.UTF8String};
    return [self runArgc:3 argv:argv];
}

@end
