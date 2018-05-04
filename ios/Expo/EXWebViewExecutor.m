#import "EXWebViewExecutor.h"

@import JavaScriptCore;
@import WebKit;

#import <React/RCTUtils.h>

typedef void (^EXJavaScriptCompletionHandler)(_Nullable id result, NSError * _Nullable error);

@interface EXWebViewExecutor () <WKNavigationDelegate>
@end

@implementation EXWebViewExecutor {
  BOOL _valid;
  WKWebView *_webView;
  JSContext *_jsContext;
  NSUInteger _nextMessageId;
  NSMutableDictionary<NSNumber *, EXJavaScriptCompletionHandler> *_completionHandlers;
}

- (instancetype)init
{
  if (self = [super init]) {
    _valid = YES;
    _webView = [[WKWebView alloc] init];
    _webView.navigationDelegate = self;
    _nextMessageId = 0;
    _completionHandlers = [NSMutableDictionary dictionary];
    _jsContext = [[JSContext alloc] init];
  }
  return self;
}

#pragma mark - RCTInvalidating

- (void)invalidate
{
  _webView = nil;
  _jsContext = nil;
  _valid = NO;
}

#pragma mark - RCTBridgeModule

RCT_EXPORT_MODULE(ExpoWebViewExecutor)

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

- (BOOL)requiresMainQueueSetup
{
  return YES;
}

#pragma mark - RCTJavaScriptExecutor

- (void)setUp
{
}

- (BOOL)isValid
{
  return _valid;
}

- (void)flushedQueue:(RCTJavaScriptCallback)onComplete
{
  [self _evaluateJavaScript:@"__fbBatchedBridge.flushedQueue()"
          completionHandler:^(id _Nullable queue, NSError * _Nullable error) {
            onComplete(queue, error);
          }];
}

- (void)callFunctionOnModule:(NSString *)module
                      method:(NSString *)method
                   arguments:(NSArray *)arguments
                    callback:(RCTJavaScriptCallback)onComplete
{
  NSData *argumentsJson = [NSJSONSerialization dataWithJSONObject:arguments options:0 error:nil];
  NSString *code = [NSString stringWithFormat:@"__fbBatchedBridge.callFunctionReturnFlushedQueue(\"%@\", \"%@\", %@)",
                    module,
                    method,
                    [[NSString alloc] initWithData:argumentsJson encoding:NSUTF8StringEncoding]];
  [self _evaluateJavaScript:code
          completionHandler:^(id _Nullable queue, NSError * _Nullable error) {
            onComplete(queue, error);
          }];
}

- (void)invokeCallbackID:(NSNumber *)callbackId
               arguments:(NSArray *)arguments
                callback:(RCTJavaScriptCallback)onComplete
{
  NSData *argumentsJson = [NSJSONSerialization dataWithJSONObject:arguments options:0 error:nil];
  NSString *code = [NSString stringWithFormat:@"__fbBatchedBridge.invokeCallbackAndReturnFlushedQueue(%ld, %@)",
                    (long)[callbackId integerValue],
                    [[NSString alloc] initWithData:argumentsJson encoding:NSUTF8StringEncoding]];
  [self _evaluateJavaScript:code
          completionHandler:^(id _Nullable queue, NSError * _Nullable error) {
            onComplete(queue, error);
          }];
}

- (void)executeApplicationScript:(NSData *)script
                       sourceURL:(NSURL *)sourceURL
                      onComplete:(RCTJavaScriptCompleteBlock)onComplete
{
  [self _evaluateJavaScript:[NSString stringWithFormat:@"%@\nundefined;",
                             [[NSString alloc] initWithData:script encoding:NSUTF8StringEncoding]]
                 withResult:NO
          completionHandler:^(id _Nullable result, NSError * _Nullable error) {
            onComplete(error);
          }];
}

- (void)injectJSONText:(NSString *)script
   asGlobalObjectNamed:(NSString *)objectName
              callback:(RCTJavaScriptCompleteBlock)onComplete
{
  [self _evaluateJavaScript:[NSString stringWithFormat:@"void (%@ = %@)", objectName, script]
                 withResult:NO
          completionHandler:^(id _Nullable queue, NSError * _Nullable error) {
            onComplete(error);
          }];
}

- (void)executeBlockOnJavaScriptQueue:(dispatch_block_t)block
{
  if ([NSOperationQueue currentQueue].underlyingQueue == dispatch_get_main_queue()) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

- (void)executeAsyncBlockOnJavaScriptQueue:(dispatch_block_t)block
{
  RCTExecuteOnMainQueue(block);
}

- (void)_evaluateJavaScript:(NSString *)code completionHandler:(void (^)(_Nullable id, NSError * _Nullable error))completionHandler
{
  [self _evaluateJavaScript:code withResult:YES completionHandler:completionHandler];
}

- (void)_evaluateJavaScript:(NSString *)code
                 withResult:(BOOL)withResult
          completionHandler:(void (^)(_Nullable id, NSError * _Nullable error))completionHandler
{
  BOOL useLocationChannel = YES;
  CFTimeInterval startTime = CACurrentMediaTime();
  if (_jsContext) {
    RCTExecuteOnMainQueue(^{
      CFTimeInterval dispatchCompleteTime = CACurrentMediaTime();
      NSLog(@"Dispatched to main thread in: %g ms", (dispatchCompleteTime - startTime) * 1000);
      if (!self->_valid) {
        return;
      }
      [self _interpretJavaScript:code completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        CFTimeInterval evaluationCompleteTime = CACurrentMediaTime();
        NSLog(@"Evaluated JS in: %g ms", (evaluationCompleteTime - dispatchCompleteTime) * 1000);
        completionHandler(result, error);
      }];
    });
//    [self _interpretJavaScript:code completionHandler:completionHandler];
  } else if (useLocationChannel) {
    RCTExecuteOnMainQueue(^{
      CFTimeInterval dispatchCompleteTime = CACurrentMediaTime();
      NSLog(@"Dispatched to main thread in: %gms", (dispatchCompleteTime - startTime) * 1000);
      if (!self->_valid) {
        return;
      }
      
      NSUInteger messageId = self->_nextMessageId;
      self->_nextMessageId++;
      self->_completionHandlers[@(messageId)] = ^(_Nullable id result, NSError * _Nullable error) {
        CFTimeInterval evaluationCompleteTime = CACurrentMediaTime();
        NSLog(@"Evaluated JS in: %gms", (evaluationCompleteTime - dispatchCompleteTime) * 1000);
        completionHandler(result, error);
      };
      
      if (withResult) {
        [self->_webView evaluateJavaScript:[NSString stringWithFormat:@"location.replace('#js-message://' + JSON.stringify({ id: %lu, result: %@ }));", messageId, code]
                         completionHandler:nil];
      } else {
        [self->_webView evaluateJavaScript:[NSString stringWithFormat:@"%@\nlocation.replace('#js-message://' + JSON.stringify({ id: %lu }));", code, messageId]
                         completionHandler:nil];
      }
    });
  } else {
    RCTExecuteOnMainQueue(^{
      CFTimeInterval dispatchCompleteTime = CACurrentMediaTime();
      NSLog(@"Dispatched to main thread in: %gms", (dispatchCompleteTime - startTime) * 1000);
      if (!self->_valid) {
        return;
      }
      [self->_webView evaluateJavaScript:code completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        CFTimeInterval evaluationCompleteTime = CACurrentMediaTime();
        NSLog(@"Evaluated JS in: %gms", (evaluationCompleteTime - dispatchCompleteTime) * 1000);
        completionHandler(result, error);
      }];
    });
  }
  
  
}

- (void)_interpretJavaScript:(NSString *)code completionHandler:(void (^)(_Nullable id, NSError * _Nullable error))completionHandler
{
  JSValue *result = [_jsContext evaluateScript:code];
  if (_jsContext.exception) {
    JSValue *exception = _jsContext.exception;
    _jsContext.exception = nil;
    
    NSError *error = [NSError errorWithDomain:@"JavaScriptError"
                                         code:0
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@\n:%@",
                                                                            exception[@"name"],
                                                                            exception[@"message"],
                                                                            exception[@"stack"]]
                                                }];
    completionHandler(nil, error);
  } else {
    completionHandler([result toObject], nil);
  }
  return;
}

# pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
  CFTimeInterval startTime = CACurrentMediaTime();
  NSString *urlString = navigationAction.request.URL.absoluteString;
  NSRange messageRange = [urlString rangeOfString:@"message://"];
  if (messageRange.location == NSNotFound) {
    decisionHandler(WKNavigationActionPolicyAllow);
    return;
  }
  
  NSString *messageJson = [urlString substringFromIndex:messageRange.location + messageRange.length].stringByRemovingPercentEncoding;
  NSDictionary *messageObject = [NSJSONSerialization JSONObjectWithData:[messageJson dataUsingEncoding:NSUTF8StringEncoding]
                                                                options:0
                                                                  error:nil];
  CFTimeInterval decodeCompleteTime = CACurrentMediaTime();
  NSLog(@"Decoded JSON response in: %gms", (decodeCompleteTime - startTime) * 1000);
  NSUInteger messageId = ((NSNumber *)messageObject[@"id"]).unsignedIntegerValue;
  _Nullable id messageResult = messageObject[@"result"];
  
  EXJavaScriptCompletionHandler completionHandler = _completionHandlers[@(messageId)];
  [_completionHandlers removeObjectForKey:@(messageId)];
  
  completionHandler(messageResult, nil);
  decisionHandler(WKNavigationActionPolicyCancel);
  
//  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
//
//  });

}

@end
