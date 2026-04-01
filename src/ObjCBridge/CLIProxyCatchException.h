#import <Foundation/Foundation.h>

/// Catches ObjC NSException thrown inside tryBlock.
/// Returns a dictionary with "name" and "reason" if an exception was caught, nil otherwise.
/// Used to wrap URLSession.dataTask(with:) which throws NSGenericException
/// when the session has been invalidated.
NSDictionary *_Nullable CLIProxyCatchException(void (^_Nonnull tryBlock)(void));
