#import "EXWebViewController.h"

@import WebKit;

NS_ASSUME_NONNULL_BEGIN

// This defines "webkit.messageHandlers.expo" in each frame of the web view
static NSString * const EXWebViewScriptHandlerName = @"expo";

@interface EXWebViewController () <WKScriptMessageHandler>

@property (nonatomic, strong) WKWebView *view;

@end

@implementation EXWebViewController

@dynamic view;

- (void)loadView
{
  CGSize rootViewSize = self.preferredContentSize;
  CGRect rootViewFrame = CGRectMake(0, 0, rootViewSize.width, rootViewSize.height);
  self.view = [[WKWebView alloc] initWithFrame:rootViewFrame
                                 configuration:[self _webViewConfiguration]];
}

- (void)viewDidLoad
{
  [self _measureLatencyNumberOfTimes:100 handler:^(NSArray<NSNumber *> *times) {
    for (NSNumber *elapsedTime in times) {
      NSLog(@"%@", elapsedTime);
    }
  }];
}

- (void)_measureLatencyNumberOfTimes:(NSUInteger)times handler:(void (^)(NSArray<NSNumber *> *times))handler;
{
  if (times == 0) {
    handler(@[]);
    return;
  }
  
  NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
  [self.view evaluateJavaScript:@"Date.now()" completionHandler:^(id _Nullable returnValue,
                                                              NSError * _Nullable error) {
    NSTimeInterval endTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval jsTime = ((NSNumber *)returnValue).doubleValue;
    NSTimeInterval jsTimeElapsed = (jsTime - startTime * 1000);
    NSTimeInterval timeElapsed = (endTime - startTime) * 1000;
    NSLog(@"Started at %lf, got JS time at %lf (%lf ms), and ended at %lf (%lf ms)",
          startTime, jsTime / 1000, jsTimeElapsed, endTime, timeElapsed);
    
    [NSThread sleepForTimeInterval:1];
    
    [self _measureLatencyNumberOfTimes:times - 1 handler:^(NSArray<NSNumber *> *times) {
      handler([@[@(timeElapsed)] arrayByAddingObjectsFromArray:times]);
    }];
  }];
}

- (WKWebViewConfiguration *)_webViewConfiguration
{
  WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
  
  WKUserContentController *userContentController = [[WKUserContentController alloc] init];
  [userContentController addScriptMessageHandler:self name:EXWebViewScriptHandlerName];
  configuration.userContentController = userContentController;
  
  return configuration;
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
}

# pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
{
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSLog(@"[%lf] %@", now * 1000, message.body);
}

@end

NS_ASSUME_NONNULL_END
