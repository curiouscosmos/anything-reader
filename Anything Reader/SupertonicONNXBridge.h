#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SupertonicONNXBridge : NSObject
+ (instancetype)sharedBridge;

- (nullable NSURL *)synthesizeText:(NSString *)text
                         voiceName:(NSString *)voiceName
                      languageCode:(NSString *)languageCode
                      modelRootURL:(NSURL *)modelRootURL
                             error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
