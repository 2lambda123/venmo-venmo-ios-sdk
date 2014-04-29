#import "VENDefines_Internal.h"
#import "NSBundle+VenmoSDK.h"
#import "NSDictionary+VenmoSDK.h"
#import "NSError+VenmoSDK.h"
#import "NSURL+VenmoSDK.h"
#import "VENBase64_Internal.h"
#import "Venmo.h"
#import "VENErrors.h"
#import "VENHMAC_SHA256_Internal.h"
#import "VENURLProtocol.h"
#import "VENSession.h"
#import "VENUser.h"

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_6_0
#import "UIDevice+IdentifierAddition.h"
#endif

static Venmo *sharedInstance = nil;

@interface Venmo ()

@property (copy, nonatomic, readwrite) NSString *appId;
@property (copy, nonatomic, readwrite) NSString *appSecret;
@property (copy, nonatomic, readwrite) NSString *appName;

@property (copy, nonatomic, readwrite) VENTransactionCompletionHandler currentTransactionCompletionHandler;
@property (copy, nonatomic, readwrite) VENOAuthCompletionHandler currentOAuthCompletionHandler;

@property (nonatomic) BOOL internalDevelopment;

@end

@implementation Venmo

#pragma mark - Initializers

+ (BOOL)startWithAppId:(NSString *)appId
                secret:(NSString *)appSecret
                  name:(NSString *)appName {
    if (sharedInstance) {
        return NO;
    }
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initWithAppId:appId secret:appSecret name:appName];
    });
    return YES;
}

+ (instancetype)sharedInstance {
    return sharedInstance;
}

- (BOOL)isConnected {
    if (!self.currentSession) {
        return NO;
    }
    return YES;
}

- (BOOL)handleOpenURL:(NSURL *)url {
    if ([VENURLProtocol canInitWithRequest:[NSURLRequest requestWithURL:url]]) {

        VENURLProtocol *urlProtocol = [[VENURLProtocol alloc] initWithRequest:[NSURLRequest requestWithURL:url] cachedResponse:nil client:nil];
        [urlProtocol startLoading];
        return YES;
    }
    return NO;
}


#pragma mark - Sending a Transaction

- (void)sendAppSwitchTransactionWithType:(VENTransactionType)type
                                  amount:(NSUInteger)amount
                                    note:(NSString *)note
                               recipient:(NSString *)recipientHandle
                       completionHandler:(VENTransactionCompletionHandler)completionHandler {
    self.currentTransactionCompletionHandler = completionHandler;
    NSString *URLPath = [self URLPathWithType:type amount:amount note:note recipient:recipientHandle];
    NSURL *transactionURL = [self venmoURLWithPath:URLPath];
    DLog(@"transactionURL: %@", transactionURL);

    if ([self hasVenmoApp]) {
        [[UIApplication sharedApplication] openURL:transactionURL];
    } else if (completionHandler) {
        NSError *error = [NSError errorWithDomain:VENErrorDomain
                                             code:VENTransactionFailedError
                                      description:@"Could not find Venmo app."
                               recoverySuggestion:@"Please install Venmo."];
        completionHandler(nil, NO, error);
    }

}

#pragma mark - OAuth

- (void)requestPermissions:(NSArray *)permissions
     withCompletionHandler:(VENOAuthCompletionHandler)completionHandler {
    NSString *scopeURLEncoded = [permissions componentsJoinedByString:@"%20"];
    self.currentOAuthCompletionHandler = completionHandler;

    NSString *baseURL;
    if ([self hasVenmoApp]) {
        baseURL = @"venmo://";
    } else {
        baseURL = [self baseURLPath];
    }
    NSURL *authURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@oauth/authorize?sdk=ios&client_id=%@&scope=%@&response_type=code", baseURL, self.appId, scopeURLEncoded]];

    [[UIApplication sharedApplication] openURL:authURL];
}


#pragma mark - Sending a Transaction @private

- (NSString *)URLPathWithType:(VENTransactionType)type
                       amount:(NSUInteger)amount
                         note:(NSString *)note
                    recipient:(NSString *)recipientHandle {
    NSString *identifier = [self currentDeviceIdentifier];

    NSString *pathAndQuery = [NSString stringWithFormat:@"/?client=ios&"
                              "app_name=%@&app_id=%@&device_id=%@",
                              self.appName,
                              self.appId,
                              identifier];
    pathAndQuery = [NSString stringWithFormat:@"%@&amount=%@", pathAndQuery, [VENTransaction amountString:amount]];
    pathAndQuery = [NSString stringWithFormat:@"%@&txn=%@", pathAndQuery, [VENTransaction typeString:type]];
    pathAndQuery = [NSString stringWithFormat:@"%@&recipients=%@", pathAndQuery, recipientHandle];
    pathAndQuery = [NSString stringWithFormat:@"%@&note=%@", pathAndQuery, note];
    pathAndQuery = [NSString stringWithFormat:@"%@&app_version=%@", pathAndQuery, VEN_CURRENT_SDK_VERSION];

    return pathAndQuery;
}


- (NSURL *)venmoURLWithPath:(NSString *)path {
    NSString *newPath = [NSString stringWithFormat:@"venmosdk://venmo.com%@", path];
    return [[NSURL alloc] initWithString:[newPath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
}


#pragma mark - Private

- (instancetype)initWithAppId:(NSString *)appId
                       secret:(NSString *)appSecret
                         name:(NSString *)appName {
    self = [super init];
    if (self) {
        self.appId = appId;
        self.appSecret = appSecret;
        self.appName = appName ?: [[NSBundle mainBundle] name];
    }
    return self;
}

- (NSString *)baseURLPath {
    if (self.internalDevelopment) {
        return @"http://api.dev.venmo.com/v1/";
    }
    return @"http://api.venmo.com/v1/";
}

- (BOOL)hasVenmoApp {
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"venmo://"]];
}

- (NSString *)currentDeviceIdentifier {
#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_6_0
    if ([[UIDevice currentDevice] respondsToSelector:@selector(identifierForVendor)]) {
        return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    } else {
        return [[UIDevice currentDevice] uniqueDeviceIdentifier];
    }
#else
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
#endif
}

@end