#import "CLIProxyCatchException.h"

NSDictionary *_Nullable CLIProxyCatchException(void (^_Nonnull tryBlock)(void)) {
    @try {
        tryBlock();
        return nil;
    } @catch (NSException *exception) {
        return @{
            @"name": exception.name,
            @"reason": exception.reason ?: @""
        };
    }
}
