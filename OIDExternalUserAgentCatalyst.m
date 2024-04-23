/*! @file OIDExternalUserAgentCatalyst.m
   @brief AppAuth iOS SDK
   @copyright
       Copyright 2019 The AppAuth Authors. All Rights Reserved.
   @copydetails
       Licensed under the Apache License, Version 2.0 (the "License");
       you may not use this file except in compliance with the License.
       You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

       Unless required by applicable law or agreed to in writing, software
       distributed under the License is distributed on an "AS IS" BASIS,
       WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
       See the License for the specific language governing permissions and
       limitations under the License.
*/

#import <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_MACCATALYST

#import "OIDExternalUserAgentCatalyst.h"

#import <SafariServices/SafariServices.h>
#import <AuthenticationServices/AuthenticationServices.h>

#import "OIDErrorUtilities.h"
#import "OIDExternalUserAgentSession.h"
#import "OIDExternalUserAgentRequest.h"

#if TARGET_OS_MACCATALYST

NS_ASSUME_NONNULL_BEGIN

@import WebKit;
@import UIKit;

@protocol OIDWebViewControllerDelegate;

@interface OIDWebViewController: UIViewController {

}
@property(nonatomic, strong) NSString *redirectScheme;
@property(nonatomic, strong) NSURL *requestURL;
@property(nonatomic, assign) id<OIDWebViewControllerDelegate> delegate;

-(void)loadContent;

@end

@protocol OIDWebViewControllerDelegate<NSObject>

-(void)webViewDidFinish:(NSURL *)callbackURL;

-(void)webViewDidClose;

@end

@interface OIDWebViewController () <WKUIDelegate, WKNavigationDelegate> {

}
@property(nonatomic, strong) WKWebView *webView;

@end

@implementation OIDWebViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  self.navigationController.navigationBar.translucent = NO;
  self.navigationController.toolbar.translucent = NO;

  [self createLeftBarButtonItem];
}

-(void)createLeftBarButtonItem
{
    if (self.navigationItem.leftBarButtonItem == nil)
    {
        UIBarButtonItem *closeButton = [[UIBarButtonItem alloc]
                                         initWithImage:[UIImage systemImageNamed:@"xmark"]
                                         style:UIBarButtonItemStylePlain
                                         target:self
                                         action:@selector(doClose:)];
        
        self.navigationItem.leftBarButtonItem = closeButton;
    }
}

-(void)doClose:(id)sender
{
   [self dismissViewControllerAnimated:YES completion:^{
        if ([self.delegate respondsToSelector:@selector(webViewDidClose)]) {
            [self.delegate webViewDidClose];
        }
   }];
}

-(void)constructView:(CGSize)boundSize
{
    if (self.webView == nil) {
        WKWebViewConfiguration *webViewConfiguration = [[WKWebViewConfiguration alloc] init];
        webViewConfiguration.allowsInlineMediaPlayback = NO;
        
        // Initialize the WKWebView with your WKWebViewConfiguration object.
        self.webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, boundSize.width, boundSize.height) configuration:webViewConfiguration];
        self.webView.navigationDelegate = self;
        self.webView.UIDelegate = self;
        self.webView.customUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15";
              
        self.webView.scrollView.bounces = NO;

        [self.view addSubview:self.webView];
    }
}

-(void)resetView:(CGSize)boundSize
{
    self.webView.frame = CGRectMake(0, 0, boundSize.width, boundSize.height);
}

-(void)actualLoadContent
{
    [self constructView:self.view.bounds.size];
	
	  [self resetView:self.view.bounds.size];

    NSURLRequest *request = [NSURLRequest requestWithURL:self.requestURL];
    [self.webView loadRequest:request];
}

-(void)loadContent
{
    [self performSelector:@selector(actualLoadContent) withObject:nil afterDelay:0.1f];
}

-(void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSString *urlString = navigationAction.request.URL.absoluteString;
    //NSLog(@"urlString: %@", urlString);
    if ([urlString hasPrefix:self.redirectScheme]) {

        [self dismissViewControllerAnimated:YES completion:^{
            if ([self.delegate respondsToSelector:@selector(webViewDidFinish:)]) {
                [self.delegate webViewDidFinish:navigationAction.request.URL];
            }
        }];

        decisionHandler(NO);
    } else {
        decisionHandler(YES);
    }
}

@end

@interface OIDExternalUserAgentCatalyst ()<ASWebAuthenticationPresentationContextProviding, OIDWebViewControllerDelegate>
@end

@implementation OIDExternalUserAgentCatalyst {
  UIViewController *_presentingViewController;
  BOOL _prefersEphemeralSession;

  BOOL _externalUserAgentFlowInProgress;
  __weak id<OIDExternalUserAgentSession> _session;
  //ASWebAuthenticationSession *_webAuthenticationVC;

  __weak OIDWebViewController *_safariVC;
}

- (nullable instancetype)initWithPresentingViewController:
    (UIViewController *)presentingViewController {
  self = [super init];
  if (self) {
    _presentingViewController = presentingViewController;
  }
  return self;
}

- (nullable instancetype)initWithPresentingViewController:
    (UIViewController *)presentingViewController
                                  prefersEphemeralSession:(BOOL)prefersEphemeralSession {
  self = [self initWithPresentingViewController:presentingViewController];
  if (self) {
    _prefersEphemeralSession = prefersEphemeralSession;
  }
  return self;
}

- (BOOL)presentExternalUserAgentRequest:(id<OIDExternalUserAgentRequest>)request
                                session:(id<OIDExternalUserAgentSession>)session {
  if (_externalUserAgentFlowInProgress) {
    // TODO: Handle errors as authorization is already in progress.
    return NO;
  }

  _externalUserAgentFlowInProgress = YES;
  _session = session;
  BOOL openedUserAgent = NO;
  NSURL *requestURL = [request externalUserAgentRequestURL];

  __weak OIDExternalUserAgentCatalyst *weakSelf = self;
  NSString *redirectScheme = request.redirectScheme;

  /*ASWebAuthenticationSession *authenticationVC =
      [[ASWebAuthenticationSession alloc] initWithURL:requestURL
                                    callbackURLScheme:redirectScheme
                                    completionHandler:^(NSURL * _Nullable callbackURL,
                                                        NSError * _Nullable error) {
    __strong OIDExternalUserAgentCatalyst *strongSelf = weakSelf;
    if (!strongSelf) {
        return;
    }
    strongSelf->_webAuthenticationVC = nil;
    if (callbackURL) {
      [strongSelf->_session resumeExternalUserAgentFlowWithURL:callbackURL];
    } else {
      NSError *safariError =
          [OIDErrorUtilities errorWithCode:OIDErrorCodeUserCanceledAuthorizationFlow
                           underlyingError:error
                               description:nil];
      [strongSelf->_session failExternalUserAgentFlowWithError:safariError];
    }
  }];
      
  authenticationVC.presentationContextProvider = self;
  authenticationVC.prefersEphemeralWebBrowserSession = _prefersEphemeralSession;
  _webAuthenticationVC = authenticationVC;
  openedUserAgent = [authenticationVC start];*/

  if (!openedUserAgent && _presentingViewController) {
      OIDWebViewController *safariVC = [[OIDWebViewController alloc] init];
      safariVC.redirectScheme = redirectScheme;
      safariVC.requestURL = requestURL;
      safariVC.delegate = self;
      _safariVC = safariVC;

      safariVC.preferredContentSize = CGSizeMake(768, [UIScreen mainScreen].bounds.size.height * 0.8);

      UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:safariVC];
      navigationController.modalInPresentation = YES;
      navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
      navigationController.navigationBar.translucent = NO;
      navigationController.toolbar.translucent = NO;
    
      [_presentingViewController presentViewController:navigationController animated:YES completion:^{

          [safariVC loadContent];
      }];
      openedUserAgent = YES;
    }

  if (!openedUserAgent) {
    [self cleanUp];
    NSError *safariError = [OIDErrorUtilities errorWithCode:OIDErrorCodeSafariOpenError
                                            underlyingError:nil
                                                description:@"Unable to open ASWebAuthenticationSession view controller."];
    [session failExternalUserAgentFlowWithError:safariError];
  }
  return openedUserAgent;
}

- (void)dismissExternalUserAgentAnimated:(BOOL)animated completion:(void (^)(void))completion {
  if (!_externalUserAgentFlowInProgress) {
    // Ignore this call if there is no authorization flow in progress.
    if (completion) completion();
    return;
  }
  
  //ASWebAuthenticationSession *webAuthenticationVC = _webAuthenticationVC;
  
  [self cleanUp];
  
  /*if (webAuthenticationVC) {
    // dismiss the ASWebAuthenticationSession
    [webAuthenticationVC cancel];
    if (completion) completion();
  } else {
    if (completion) completion();
  }*/

  if (completion) completion();
} 

- (void)cleanUp {
  // The weak reference to |_session| is set to nil to avoid accidentally using
  // it while not in an authorization flow.
  //_webAuthenticationVC = nil;
  _session = nil;
  _externalUserAgentFlowInProgress = NO;
}

#pragma mark - SFSafariViewControllerDelegate

-(void)webViewDidFinish:(NSURL *)callbackURL 
{
    __weak OIDExternalUserAgentCatalyst *weakSelf = self;

    __strong OIDExternalUserAgentCatalyst *strongSelf = weakSelf;
    if (!strongSelf) {
        return;
    }
    //strongSelf->_webAuthenticationVC = nil;
    if (callbackURL) {
      [strongSelf->_session resumeExternalUserAgentFlowWithURL:callbackURL];
    } else {
      NSError *safariError =
          [OIDErrorUtilities errorWithCode:OIDErrorCodeUserCanceledAuthorizationFlow
                           underlyingError:nil
                               description:@"Unexpected Error"];
      [strongSelf->_session failExternalUserAgentFlowWithError:safariError];
    }
}

-(void)webViewDidClose
{
      __weak OIDExternalUserAgentCatalyst *weakSelf = self;

      __strong OIDExternalUserAgentCatalyst *strongSelf = weakSelf;
      if (!strongSelf) {
          return;
      }
      
      NSError *safariError =
          [OIDErrorUtilities errorWithCode:OIDErrorCodeUserCanceledAuthorizationFlow
                           underlyingError:nil
                               description:@"Unexpected Error"];

      //NSLog(@"webViewDidClose: error: %@", error);
      [strongSelf->_session failExternalUserAgentFlowWithError:safariError];
}

#pragma mark - ASWebAuthenticationPresentationContextProviding

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
  return _presentingViewController.view.window;
}

@end

NS_ASSUME_NONNULL_END

#endif // TARGET_OS_MACCATALYST

#endif // TARGET_OS_IOS || TARGET_OS_MACCATALYST
