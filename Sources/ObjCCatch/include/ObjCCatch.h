#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, converting an Objective-C exception into an NSError.
/// AVFoundation reports some misuse (e.g. a tap format that no longer matches the
/// hardware after a Bluetooth profile switch) by raising, which Swift can't catch.
BOOL HSCatchObjCException(NS_NOESCAPE void (^block)(void), NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
