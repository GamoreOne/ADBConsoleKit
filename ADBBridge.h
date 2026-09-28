#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ADBBridgeObjC : NSObject

+ (instancetype)shared;

- (NSString *)connect:(NSString *)host port:(NSString *)port;
- (NSString *)disconnect:(NSString *)host port:(NSString *)port;
- (NSString *)shell:(NSString *)command;
- (NSString *)run:(NSString *)command;
- (NSString *)installAPK:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
