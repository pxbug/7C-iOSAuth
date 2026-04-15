//
//  GoAuth.m
//  Go
//
//  Created by CloZhi on 2026/2/26.
//

#import "GoAuth.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

// API配置
#define kAPIHost         @"http://api1.7ccccccc.com"
#define kCardLoginPath   @"/v1/card/login"
#define kAppKey          @"2c1YZQVjPwzbLZVN3U"
#define kAppSecret       @"lDzDCinXSsEBa2VLj4dwNYynXOgqLGz7"

static NSString *const kTokenKey      = @"GoAuth_Token";
static NSString *const kExpiresKey    = @"GoAuth_Expires";
static NSString *const kCardKey       = @"GoAuth_Card";

#pragma mark - MD5签名辅助

static NSString* GoAuth_MD5(NSString *input) {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

static NSString* GoAuth_GenerateNonce(void) {
    return [[NSUUID UUID] UUIDString];
}

static NSString* GoAuth_GetDeviceID(void) {
    NSString *deviceID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    return deviceID ?: @"unknown_device";
}

static NSString* GoAuth_GenerateSign(NSDictionary *params) {
    NSMutableString *signString = [NSMutableString string];
    
    [signString appendString:@"POST"];
    [signString appendString:@"api1.7ccccccc.com"];
    [signString appendString:@"/v1/card/login"];
    
    NSArray *sortedKeys = [[params allKeys] sortedArrayUsingSelector:@selector(compare:)];
    BOOL first = YES;
    for (NSString *key in sortedKeys) {
        if ([key isEqualToString:@"sign"]) continue;
        [signString appendFormat:@"%@%@=%@", first ? @"" : @"&", key, params[key]];
        first = NO;
    }
    [signString appendString:kAppSecret];
    
    NSLog(@"GoAuth 签名内容: %@", signString);
    NSLog(@"GoAuth 签名结果: %@", GoAuth_MD5(signString));
    
    return GoAuth_MD5(signString);
}

#pragma mark - Token存储

static void GoAuth_SaveToken(NSString *token, NSString *expires, NSString *card) {
    [[NSUserDefaults standardUserDefaults] setObject:token forKey:kTokenKey];
    [[NSUserDefaults standardUserDefaults] setObject:expires forKey:kExpiresKey];
    [[NSUserDefaults standardUserDefaults] setObject:card forKey:kCardKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL GoAuth_IsTokenValid(void) {
    NSString *expires = [[NSUserDefaults standardUserDefaults] stringForKey:kExpiresKey];
    if (!expires) return NO;
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSDate *expiresDate = [formatter dateFromString:expires];
    
    return expiresDate && [expiresDate compare:[NSDate date]] == NSOrderedDescending;
}

#pragma mark - UI提示(3秒自动消失)

static UIAlertController *g_currentAlert = nil;

static void GoAuth_ShowAutoDismissAlert(NSString *title, NSString *message, void (^completion)(void)) {
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    
    g_currentAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    
    [vc presentViewController:g_currentAlert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (g_currentAlert.presentingViewController) {
                [g_currentAlert dismissViewControllerAnimated:YES completion:^{
                    g_currentAlert = nil;
                    if (completion) completion();
                }];
            } else {
                g_currentAlert = nil;
                if (completion) completion();
            }
        });
    }];
}

#pragma mark - 激活弹窗

static void GoAuth_showCardAlert(void);

static void GoAuth_PerformLogin(NSString *card) {
    NSString *nonce = GoAuth_GenerateNonce();
    NSString *timestamp = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSString *deviceID = GoAuth_GetDeviceID();
    
    NSDictionary *params = @{
        @"appKey": kAppKey,
        @"card": card,
        @"device_id": deviceID,
        @"nonce": nonce,
        @"timestamp": timestamp
    };
    
    NSString *sign = GoAuth_GenerateSign(params);
    
    NSMutableDictionary *bodyParams = [params mutableCopy];
    bodyParams[@"sign"] = sign;
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", kAPIHost, kCardLoginPath]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    request.timeoutInterval = 30.0;
    
    NSMutableString *bodyString = [NSMutableString string];
    NSArray *sortedKeys = [[bodyParams allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        if (bodyString.length > 0) [bodyString appendString:@"&"];
        [bodyString appendFormat:@"%@=%@", key, bodyParams[key]];
    }
    request.HTTPBody = [bodyString dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                GoAuth_ShowAutoDismissAlert(@"网络错误", @"请求失败，请检查网络连接", ^{
                    GoAuth_showCardAlert();
                });
                return;
            }
            
            NSError *parseError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            if (!json) {
                GoAuth_ShowAutoDismissAlert(@"解析错误", @"服务器响应格式错误", ^{
                    GoAuth_showCardAlert();
                });
                return;
            }
            
            NSInteger code = [json[@"code"] integerValue];
            NSString *message = json[@"message"] ?: @"未知错误";
            
            if (code == 0) {
                NSDictionary *result = json[@"result"];
                NSString *token = result[@"token"];
                NSString *expires = result[@"expires"];
                
                GoAuth_SaveToken(token, expires, card);
                GoAuth_ShowAutoDismissAlert(@"激活成功", [NSString stringWithFormat:@"过期时间: %@", expires], nil);
            } else {
                GoAuth_ShowAutoDismissAlert(@"激活失败", message, ^{
                    GoAuth_showCardAlert();
                });
            }
        });
    }];
    [task resume];
}

static void GoAuth_showCardAlert(void) {
    if (GoAuth_IsTokenValid()) return;

    NSString *savedCard = [[NSUserDefaults standardUserDefaults] stringForKey:kCardKey];
    if (savedCard.length > 0) {
        GoAuth_PerformLogin(savedCard);
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *viewController = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (viewController.presentedViewController) {
            if ([viewController.presentedViewController isKindOfClass:[UIAlertController class]]) return;
            viewController = viewController.presentedViewController;
        }
        if (!viewController) return;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"温馨提示"
                                                                     message:@"请输入您的激活卡密"
                                                              preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"请输入激活码";
            textField.clearButtonMode = UITextFieldViewModeAlways;
            textField.keyboardType = UIKeyboardTypeDefault;
        }];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"激活"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            NSString *card = alert.textFields.firstObject.text ?: @"";
            if (card.length == 0) {
                GoAuth_ShowAutoDismissAlert(@"提示", @"请输入激活码", ^{
                    GoAuth_showCardAlert();
                });
            } else {
                GoAuth_PerformLogin(card);
            }
        }]];
        
        [viewController presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - 构造函数入口

static void __attribute__((constructor)) GoAuth_Init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        GoAuth_showCardAlert();
    });
}
