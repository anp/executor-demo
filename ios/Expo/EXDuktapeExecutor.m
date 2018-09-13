#import "EXDuktapeExecutor.h"

@import JavaScriptCore;
@import WebKit;

#import <React/RCTUtils.h>

typedef void (^EXJavaScriptCompletionHandler)(_Nullable id result, NSError *_Nullable error);

@implementation EXDuktapeExecutor {
    BOOL _valid;
    duk_context *_dukContext;
    NSMutableDictionary<NSNumber *, EXJavaScriptCompletionHandler> *_completionHandlers;
}

- (instancetype)init {
    if (self = [super init]) {
        _valid = YES;
        _dukContext = duk_create_heap_default();
        _completionHandlers = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - RCTInvalidating

- (void)invalidate {
    duk_destroy_heap(_dukContext);
    _dukContext = nil;
    _valid = NO;
}

#pragma mark - RCTBridgeModule

RCT_EXPORT_MODULE(ExpoDuktapeExecutor)

#pragma mark - RCTJavaScriptExecutor

- (void)setUp {
}

- (BOOL)isValid {
    return _valid;
}

- (void)flushedQueue:(RCTJavaScriptCallback)onComplete {
    [self _evaluateJavaScript:@"__fbBatchedBridge.flushedQueue()"
            completionHandler:^(id _Nullable queue, NSError *_Nullable error) {
                onComplete(queue, error);
            }];
}

- (void)callFunctionOnModule:(NSString *)module
                      method:(NSString *)method
                   arguments:(NSArray *)arguments
                    callback:(RCTJavaScriptCallback)onComplete {
    NSData *argumentsJson = [NSJSONSerialization dataWithJSONObject:arguments options:0 error:nil];
    NSString *code = [NSString stringWithFormat:@"__fbBatchedBridge.callFunctionReturnFlushedQueue(\"%@\", \"%@\", %@)",
                                                module,
                                                method,
                                                [[NSString alloc] initWithData:argumentsJson encoding:NSUTF8StringEncoding]];
    [self _evaluateJavaScript:code
            completionHandler:^(id _Nullable queue, NSError *_Nullable error) {
                onComplete(queue, error);
            }];
}

- (void)invokeCallbackID:(NSNumber *)callbackId
               arguments:(NSArray *)arguments
                callback:(RCTJavaScriptCallback)onComplete {
    NSData *argumentsJson = [NSJSONSerialization dataWithJSONObject:arguments options:0 error:nil];
    NSString *code = [NSString stringWithFormat:@"__fbBatchedBridge.invokeCallbackAndReturnFlushedQueue(%ld, %@)",
                                                (long) [callbackId integerValue],
                                                [[NSString alloc] initWithData:argumentsJson encoding:NSUTF8StringEncoding]];
    [self _evaluateJavaScript:code
            completionHandler:^(id _Nullable queue, NSError *_Nullable error) {
                onComplete(queue, error);
            }];
}

- (void)executeApplicationScript:(NSData *)script
                       sourceURL:(NSURL *)sourceURL
                      onComplete:(RCTJavaScriptCompleteBlock)onComplete {
    [self _evaluateJavaScript:[NSString stringWithFormat:@"%@\nundefined;",
                                                         [[NSString alloc] initWithData:script encoding:NSUTF8StringEncoding]]
                   withResult:NO
            completionHandler:^(id _Nullable result, NSError *_Nullable error) {
                onComplete(error);
            }];
}

- (void)injectJSONText:(NSString *)script
   asGlobalObjectNamed:(NSString *)objectName
              callback:(RCTJavaScriptCompleteBlock)onComplete {
    [self _evaluateJavaScript:[NSString stringWithFormat:@"void (%@ = %@)", objectName, script]
                   withResult:NO
            completionHandler:^(id _Nullable queue, NSError *_Nullable error) {
                onComplete(error);
            }];
}

- (void)executeBlockOnJavaScriptQueue:(dispatch_block_t)block {
    if ([NSOperationQueue currentQueue].underlyingQueue == dispatch_get_main_queue()) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

- (void)executeAsyncBlockOnJavaScriptQueue:(dispatch_block_t)block {
    RCTExecuteOnMainQueue(block);
}

- (void)_evaluateJavaScript:(NSString *)code completionHandler:(void (^)(_Nullable id, NSError *_Nullable error))completionHandler {
    [self _evaluateJavaScript:code withResult:YES completionHandler:completionHandler];
}

- (void)_evaluateJavaScript:(NSString *)code
                 withResult:(BOOL)withResult
          completionHandler:(void (^)(_Nullable id, NSError *_Nullable error))completionHandler {
    CFTimeInterval startTime = CACurrentMediaTime();
    if (_dukContext) {
        RCTExecuteOnMainQueue(^{
            CFTimeInterval dispatchCompleteTime = CACurrentMediaTime();
            NSLog(@"Dispatched to main thread in: %g ms", (dispatchCompleteTime - startTime) * 1000);
            if (!self->_valid) {
                return;
            }
            [self _interpretJavaScript:code completionHandler:^(id _Nullable result, NSError *_Nullable error) {
                CFTimeInterval evaluationCompleteTime = CACurrentMediaTime();
                NSLog(@"Evaluated JS in: %g ms", (evaluationCompleteTime - dispatchCompleteTime) * 1000);
                completionHandler(result, error);
            }];
        });
    }
}

- (void)_interpretJavaScript:(NSString *)code completionHandler:(void (^)(_Nullable id, NSError *_Nullable error))completionHandler {
    if (_dukContext) {
        duk_eval_string(_dukContext, [code UTF8String]);

        if (duk_is_error(_dukContext, -1)) {
            duk_get_prop_string(_dukContext, -1, "name");
            NSString *name = [NSString stringWithUTF8String:duk_safe_to_string(_dukContext, -1)];
            duk_pop(_dukContext);

            duk_get_prop_string(_dukContext, -1, "stack");
            NSString *stack = [NSString stringWithUTF8String:duk_safe_to_string(_dukContext, -1)];
            duk_pop(_dukContext);

            duk_get_prop_string(_dukContext, -1, "message");
            NSString *message = [NSString stringWithUTF8String:duk_safe_to_string(_dukContext, -1)];
            duk_pop(_dukContext);

            NSError *error = [NSError errorWithDomain:@"JavaScriptError"
                                                 code:0 userInfo:@{
                            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@\n:%@", name, message, stack]}];
        } else {
            const char *json = duk_json_encode(_dukContext, -1);
            if (json) {
                NSString *jsonStr = [NSString stringWithUTF8String:json];
                NSData *data = [jsonStr dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
                completionHandler([NSJSONSerialization JSONObjectWithData:data options:nil error:nil], nil);
            } else {
                completionHandler(nil, nil);
            }
        }

        duk_pop(_dukContext);
    }

    return;
}

@end
