#import "EXAppViewController.h"

#import "EXWebViewExecutor.h"

#import <React/RCTBridge.h>
#import <React/RCTRootView.h>

@implementation EXAppViewController

- (void)loadView
{
  // We need to set the executor class before the initializer runs
  RCTBridge *bridge = [RCTBridge alloc];
  bridge.executorClass = [EXWebViewExecutor class];
  NSString *index = @"http://localhost:8081/index.bundle?platform=ios";
  NSString *rnTester = @"http://localhost:8081/RNTesterApp.ios.bundle?platform=ios";
  NSString *hostedRNTester = @"https://s3-us-west-1.amazonaws.com/zorro-test-assets/RNTesterApp.ios.js.gz";
  bridge = [bridge initWithBundleURL:[NSURL URLWithString:hostedRNTester]
                      moduleProvider:^{
                        return @[];
                      }
                       launchOptions:nil];
  
  RCTRootView *rootView = [[RCTRootView alloc] initWithBridge:bridge moduleName:@"RNTesterApp" initialProperties:@{}];
  rootView.frame = CGRectMake(0, 0, self.preferredContentSize.width, self.preferredContentSize.height);
  self.view = rootView;
}

@end
