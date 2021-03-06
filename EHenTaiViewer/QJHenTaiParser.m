//
//  QJHenTaiParser.m
//  EHenTaiViewer
//
//  Created by QinJ on 2017/5/19.
//  Copyright © 2017年 kayanouriko. All rights reserved.
//
//  TODO:移动数据网络状态下的请求可以使用allowsCellularAccess属性来控制,现在的逻辑每次请求直接根据布尔值判断,比较蠢,待处理

#import "QJHenTaiParser.h"
#import "TFHpple.h"
#import "QJNetworkTool.h"
#import "QJBigImageItem.h"
#import "QJListItem.h"
#import "QJGalleryItem.h"
#import "QJTorrentItem.h"

#define kConfigurationIdentifier @"EHenTaiViewer"

@interface QJHenTaiParser ()<NSURLSessionDelegate>

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSArray<NSString *> *classifyArr;
@property (nonatomic, strong) NSArray<UIColor *> *colorArr;

@end

@implementation QJHenTaiParser

#pragma mark -创建一个单例
+ (instancetype)parser {
    static QJHenTaiParser *parser = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        parser = [QJHenTaiParser new];
    });
    return parser;
}

#pragma mark -登陆表单提交
- (void)loginWithUserName:(NSString *)username password:(NSString *)password complete:(LoginHandler)completion {
    NetworkShow();
    NSDictionary *jsonDictionary = @{
                                     @"UserName": username,
                                     @"PassWord": password,
                                     @"x":@12,//???
                                     @"y":@8//???
                                     };
    NSString *apiurl = @"https://forums.e-hentai.org/index.php?act=Login&CODE=01&CookieDate=1";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:apiurl]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[self getFormStringWithDict:jsonDictionary] dataUsingEncoding:NSUTF8StringEncoding];
    NSURLSessionTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NetworkHidden();
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"网络有点小问题呢...");
                completion(QJHenTaiParserStatusNetworkFail);
            });
            return;
        }
        if ([self checkCookie]) {
            //登陆成功
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if ([self saveUserNameWithString:html isWeb:NO]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ToastSuccess(nil, @"登陆成功!");
                    completion(QJHenTaiParserStatusSuccess);
                });
            }
            else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ToastWarning(nil, @"可能网站结构变了,没获取到你的名字呢,但是登陆成功了哦~");
                    completion(QJHenTaiParserStatusParseFail);
                });
            }
        } else {
            //登陆失败
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"登陆失败了呢,可以尝试网页登陆...");
                completion(QJHenTaiParserStatusParseFail);
            });
        }
        
    }];
    [task resume];
}

#pragma mark -获取用户名
- (BOOL)saveUserNameWithString:(NSString *)html isWeb:(BOOL)isWeb {
    NSString *regexStr = isWeb ? @"<p>You are now logged in as.*?<br>" : @"<p>You are now logged in as.*?<br />";
    NSString *userName = [[self matchString:html toRegexString:regexStr].firstObject copy];
    userName = [userName stringByReplacingOccurrencesOfString:@"<p>You are now logged in as: " withString:@""];
    userName = [userName stringByReplacingOccurrencesOfString:isWeb ? @"<br>" : @"<br />" withString:@""];
    if (userName.length) {
        NSObjSetForKey(@"loginName", userName);
        NSObjSynchronize();
        return YES;
    }
    return NO;
}

- (NSString *)getFormStringWithDict:(NSDictionary *)dict {
    NSMutableArray *queries = [NSMutableArray array];
    for (NSString *key in dict.allKeys) {
        [queries addObject:[NSString stringWithFormat:@"%@=%@", key, dict[key]]];
    }
    return [queries componentsJoinedByString:@"&"];
}

- (BOOL)checkCookie {
    NSURL *hentaiURL = [NSURL URLWithString:@"http://g.e-hentai.org"];
    for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:hentaiURL]) {
        if ([cookie.name isEqualToString:@"ipb_pass_hash"]) {
            if ([[NSDate date] compare:cookie.expiresDate] != NSOrderedAscending) {
                return NO;
            }
            else {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)deleteCokie {
    NSURL *hentaiURL = [NSURL URLWithString:@"http://g.e-hentai.org"];
    NSHTTPCookieStorage *cookieJar = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [cookieJar cookiesForURL:hentaiURL]) {
        [cookieJar deleteCookie:cookie];
    }
    NSObjSetForKey(@"loginName", @"未登录");
    NSObjSynchronize();
    return YES;
}

#pragma mark -收藏
- (void)updateFavoriteStatus:(BOOL)isFavorite model:(QJListItem *)item index:(NSInteger)index content:(NSString *)content complete:(LoginHandler)completion {
    NetworkShow();
    NSString *url = [NSString stringWithFormat:@"%@gallerypopups.php?gid=%@&t=%@&act=addfav",[NSMutableString stringWithString:[NSObjForKey(@"ExHentaiStatus") boolValue] ? EXHENTAI_URL : HENTAI_URL],item.gid ,item.token];
    NSDictionary *dict = [NSDictionary new];
    if (isFavorite) {
        //删除
        dict = @{
                 @"favcat":@"favdel",
                 @"favnote":@"",//留言
                 @"apply":@"Apply Changes",
                 @"update":@"1"
                 };
    } else {
        //添加
        dict = @{
                 @"favcat":@(index),
                 @"favnote":content,//留言
                 @"apply":@"Add to Favorites",
                 @"update":@"1"
                 };
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[self getFormStringWithDict:dict] dataUsingEncoding:NSUTF8StringEncoding];
    NSURLSessionTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NetworkHidden();
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"网络有点小问题呢...");
                completion(QJHenTaiParserStatusNetworkFail);
            });
            return;
        }
        if ([[[NSString alloc] initWithData:data  encoding:NSUTF8StringEncoding] containsString:@"Close Window"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(QJHenTaiParserStatusSuccess);
            });
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastWarning(nil, @"可能网站结构变了,没解析到操作状态呢,但是应该是操作成功了哦~");
                completion(QJHenTaiParserStatusSuccess);
            });
        }
    }];
    [task resume];
}

#pragma mark -评论
//评论存在重定向,提交后直接拦截重定向
//所以不能用全局的Session,用局部的新定义Session
- (void)updateCommentWithContent:(NSString *)content url:(NSString *)url complete:(LoginHandler)completion {
    NetworkShow();
    NSDictionary *dict = @{
                           @"commenttext":content,
                           @"postcomment":@"Post Comment"
                           };
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[self getFormStringWithDict:dict] dataUsingEncoding:NSUTF8StringEncoding];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.HTTPShouldSetCookies = YES;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:[NSOperationQueue currentQueue]];
    NSURLSessionDataTask *task = [urlSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NetworkHidden();
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"网络有点小问题呢...");
                completion(QJHenTaiParserStatusNetworkFail);
            });
            return;
        }
        NSHTTPURLResponse *urlResponse = (NSHTTPURLResponse *)response;
        if (urlResponse.statusCode == 301 || urlResponse.statusCode == 302) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastSuccess(nil, @"回复成功!");
                completion(QJHenTaiParserStatusSuccess);
            });
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastWarning(nil, @"可能网站结构变了,没解析到操作状态呢,但是应该是回复成功了哦~");
                completion(QJHenTaiParserStatusSuccess);
            });
        }
    }];
    [task resume];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * __nullable))completionHandler {
    completionHandler(nil);
}

#pragma mark -列表爬取
- (void)updateListInfoWithUrl:(NSString *)url complete:(ListHandler)completion {
    [self requestListInfo:url searchRule:@"//div [@class='it5']//a" complete:completion];
}

#pragma mark -热门爬取
- (void)updateHotListInfoComplete:(ListHandler)completion {
    [self requestListInfo:nil searchRule:@"//div [@class='id3']//a" complete:completion];
}

#pragma mark -收藏爬取
- (void)updateLikeListInfoWithUrl:(NSString *)url complete:(ListHandler)completion {
    [self updateListInfoWithUrl:url complete:completion];
}

#pragma mark -上传人和tag爬取
- (void)updateOtherListInfoWithUrl:(NSString *)url complete:(ListHandler)completion {
    [self updateListInfoWithUrl:url complete:completion];
}

- (void)requestListInfo:(NSString *)url searchRule:(NSString *)searchRule complete:(ListHandler)completion {
    /*
    //对网络做处理
    BOOL canWatch = [NSObjForKey(@"WatchMode") boolValue];
    if (!canWatch && [[QJNetworkTool shareTool] isEnableMobleNetwork]) {
        return;
    }
     */
    //正常的处理流程
    NetworkShow();
    NSString *finalUrl = @"";
    if (url) {
        if ([url hasPrefix:@"http"]) {
            finalUrl = url;
        } else {
            NSMutableString *baseUrl = [NSMutableString stringWithString:[NSObjForKey(@"ExHentaiStatus") boolValue] ? EXHENTAI_URL : HENTAI_URL];
            [baseUrl appendString:url];
            finalUrl = baseUrl;
        }
    } else {
        finalUrl = HENTAI_URL;
    }
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:[NSURL URLWithString:finalUrl] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NetworkHidden();
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"网络有点小问题呢...");
                completion(QJHenTaiParserStatusNetworkFail, nil);
            });
            return;
        }
        NSString *html = [[NSString alloc] initWithData:data  encoding:NSUTF8StringEncoding];
        if ([html containsString:@"No hits found"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastWarning(nil, @"没有更多数据...");
                completion(QJHenTaiParserStatusParseNoMore, nil);
            });
            return;
        }
        TFHpple *xpathParser = [[TFHpple alloc] initWithHTMLData:data];
        //NSLog(@"%@",[[NSString alloc] initWithData:data  encoding:NSUTF8StringEncoding]);
        NSArray *photoURL = [xpathParser searchWithXPathQuery:searchRule];
        if (photoURL.count) {
            NSMutableArray *urlStringArray = [NSMutableArray array];
            for (TFHppleElement * eachTitleWithURL in photoURL) {
                [urlStringArray addObject:[eachTitleWithURL attributes][@"href"]];
            }
            [self requestListInfoFromApi:urlStringArray complete:^(QJHenTaiParserStatus status, NSArray<QJListItem *> *listArray) {
                if (status == QJHenTaiParserStatusSuccess) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(status,listArray);
                    });
                }
                else if (status == QJHenTaiParserStatusParseFail) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        ToastError(nil, @"可能网站结构变了,解析有点小问题呢...请等待升级版本");
                        completion(QJHenTaiParserStatusParseFail,nil);
                    });
                }
                else if (status == QJHenTaiParserStatusNetworkFail) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        ToastError(nil, @"网络有点小问题呢...");
                        completion(QJHenTaiParserStatusNetworkFail,nil);
                    });
                }
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"可能网站结构变了,解析有点小问题呢...请等待升级版本");
                completion(QJHenTaiParserStatusParseFail, nil);
            });
        }
    }];
    [task resume];
}

- (void)requestListInfoFromApi:(NSArray *)urlArr complete:(ListHandler)completion {
    NetworkShow();
    NSMutableArray *idArray = [NSMutableArray array];
    for (NSString *eachURLString in urlArr) {
        NSArray *splitStrings = [eachURLString componentsSeparatedByString:@"/"];
        NSUInteger splitCount = [splitStrings count];
        [idArray addObject:@[splitStrings[splitCount - 3], splitStrings[splitCount - 2]]];
    }
    NSDictionary *jsonDictionary = @{ @"method": @"gdata", @"gidlist":idArray };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDictionary options:NSJSONWritingPrettyPrinted error:nil];
    NSString *apiurl = [NSObjForKey(@"ExHentaiStatus") boolValue] ? EXHENTAI_APIURL : HENTAI_APIURL;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:apiurl]];
    request.HTTPMethod = @"POST";
    request.HTTPBody =jsonData;
    NSURLSessionTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NetworkHidden();
        if (error) {
            completion(QJHenTaiParserStatusNetworkFail, nil);
            return;
        }
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        NSArray *listArr = dict[@"gmetadata"];
        if (listArr) {
            NSMutableArray *newArr = [NSMutableArray new];
            for (NSInteger i = 0; i < listArr.count; i++) {
                NSDictionary *dict = listArr[i];
                QJListItem *item = [[QJListItem alloc] initWithDict:dict classifyArr:self.classifyArr colorArr:self.colorArr];
                item.url = urlArr[i];
                [newArr addObject:item];
            }
            completion(QJHenTaiParserStatusSuccess, newArr);
        }
        else {
            completion(QJHenTaiParserStatusParseFail, nil);
        }
    }];
    [task resume];
}

//根据正则表达式筛选
- (NSArray *)matchString:(NSString *)string toRegexString:(NSString *)regexStr {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexStr options:NSRegularExpressionCaseInsensitive error:nil];
    NSArray * matches = [regex matchesInString:string options:0 range:NSMakeRange(0, [string length])];
    //match: 所有匹配到的字符,根据() 包含级
    NSMutableArray *array = [NSMutableArray array];
    for (NSTextCheckingResult *match in matches) {
        for (int i = 0; i < [match numberOfRanges]; i++) {
            //以正则中的(),划分成不同的匹配部分
            NSString *component = [string substringWithRange:[match rangeAtIndex:i]];
            [array addObject:component];
        }
    }
    return array;
}

#pragma mark -画廊信息解析
- (void)updateGalleryInfoWithUrl:(NSString *)url complete:(GalleryHandler)completion {
    //?inline_set=ts_m 小图,40一页
    //?inline_set=ts_l 大图,20一页
    NSString *finalUrl = [NSString stringWithFormat:@"%@?inline_set=ts_l&nw=always",url];
    NetworkShow();
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:[NSURL URLWithString:finalUrl] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"网络有点小问题呢...");
                completion(QJHenTaiParserStatusNetworkFail, nil);
            });
            return;
        }
        if ([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] containsString:@"This gallery has been removed"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"该画廊已被删除!");
                completion(QJHenTaiParserStatusParseFail,nil);
            });
            return;
        }
        TFHpple *xpathParser = [[TFHpple alloc] initWithHTMLData:data];
        QJGalleryItem *item = [[QJGalleryItem alloc] initWithHpple:xpathParser];
        if (nil == item.testUrl && !item.testUrl.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"可能网站结构变了,解析有点小问题呢...请等待升级版本");
                completion(QJHenTaiParserStatusParseFail,nil);
            });
            return;
        }
        
        [self getShowkeyWithUrl:item.testUrl complete:^(QJHenTaiParserStatus status, NSString *showkey) {
            NetworkHidden();
            if (status == QJHenTaiParserStatusSuccess) {
                item.showkey = showkey;
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(QJHenTaiParserStatusSuccess,item);
                });
            }
            else if (status == QJHenTaiParserStatusParseFail) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(QJHenTaiParserStatusParseFail,nil);
                });
            }
            else if (status == QJHenTaiParserStatusNetworkFail) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(QJHenTaiParserStatusNetworkFail,nil);
                });
            }
        }];
    }];
    [task resume];
}

- (void)getShowkeyWithUrl:(NSString *)url complete:(ShowkeyHandler)completion {
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NetworkHidden();
        if (error) {
            completion(QJHenTaiParserStatusNetworkFail,nil);
            return;
        }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *regexStr = @"var showkey=\".*?\";";
        NSString *showkey = [[self matchString:html toRegexString:regexStr].firstObject copy];
        showkey = [showkey stringByReplacingOccurrencesOfString:@"var showkey=\"" withString:@""];
        showkey = [showkey stringByReplacingOccurrencesOfString:@"\";" withString:@""];
        if (showkey.length) {
            completion(QJHenTaiParserStatusSuccess,showkey);
        }
        else {
            completion(QJHenTaiParserStatusParseFail,nil);
        }
    }];
    [task resume];
}

#pragma mark -大图链接爬取
- (void)updateBigImageUrlWithShowKey:(NSString *)showkey gid:(NSString *)gid url:(NSString *)url count:(NSInteger)count complete:(BigImageListHandler)completion {
    //页码从0开始,40一页
    NSMutableArray *newArr = [NSMutableArray new];
    for (NSInteger i = 1; i <= count; i++) {
        QJBigImageItem *item = [QJBigImageItem new];
        item.page = i;
        [newArr addObject:item];
    }
    completion(newArr);
    NSInteger total = count % 40 == 0 ? count / 40 : count / 40 + 1;
    for (NSInteger i = 0; i < total; i++) {
        [self updateBigImageUrlWithUrl:url page:i showKey:showkey gid:gid array:newArr];
    }
}

- (void)updateBigImageUrlWithUrl:(NSString *)url page:(NSInteger)page showKey:(NSString *)showkey gid:(NSString *)gid array:(NSArray<QJBigImageItem *> *)array {
    //页码从0开始,40一页
    NSString *finalUrl = @"";
    if (page == 0) {
        finalUrl = [NSString stringWithFormat:@"%@?inline_set=ts_m",url];
    }
    else {
        finalUrl = [NSString stringWithFormat:@"%@?inline_set=ts_m&p=%ld",url,(long)page];
    }
    NetworkShow();
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:[NSURL URLWithString:finalUrl] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"网络有点小问题呢...");
            });
            return;
        }
        TFHpple *xpathParser = [[TFHpple alloc] initWithHTMLData:data];
        NSArray *pageURL  = [xpathParser searchWithXPathQuery:@"//div [@class='gdtm']//a"];
        
        for (NSInteger i = 0; i < pageURL.count; i++) {
            TFHppleElement *e = pageURL[i];
            QJBigImageItem *item = array[i + page * 40];
            NSString *url = e.attributes[@"href"];
            if (!url) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ToastError(nil, @"可能网站结构变了,解析有点小问题呢...请等待升级版本");
                });
                break;
            }
            //https://e-hentai.org/s/4d74e00bc9/1070576-42
            //4d74e00bc9 为imagekey
            NSArray *arr = [url componentsSeparatedByString:@"/"];
            NSString *imageKey = arr[arr.count - 2];
            
            [self updateBigImageUrlWithShowKey:showkey gid:gid imgkey:imageKey page:item.page complete:^(QJHenTaiParserStatus status, NSString *url,NSString *x ,NSString *y) {
                if (status == QJHenTaiParserStatusSuccess) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        item.realImageUrl = url;
                        item.x = x;
                        item.y = y;
                    });
                }
            }];
        }
    }];
    [task resume];
}

#pragma mark -大图爬取
- (void)updateBigImageUrlWithShowKey:(NSString *)showkey gid:(NSString *)gid imgkey:(NSString *)imgkey page:(NSInteger)page complete:(BigImageHandler)completion {
    NetworkShow();
    NSDictionary *jsonDictionary = @{
                                     @"method": @"showpage",
                                     @"gid": gid,
                                     @"page": @(page),
                                     @"imgkey": imgkey,
                                     @"showkey": showkey
                                     };
    NSString *apiurl = [NSObjForKey(@"ExHentaiStatus") boolValue] ? EXHENTAI_APIURL : HENTAI_APIURL;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:apiurl]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:jsonDictionary options:NSJSONWritingPrettyPrinted error:nil];
    NSURLSessionTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NetworkHidden();
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"网络有点小问题呢...");
                completion(QJHenTaiParserStatusNetworkFail,nil,nil,nil);
            });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        NSString *html = json[@"i3"];
        
        NSString *regexStr = @"<img id=\"img\" src=\".*?\" style=\"";
        NSString *url = [[self matchString:html toRegexString:regexStr].firstObject copy];
        url = [url stringByReplacingOccurrencesOfString:@"<img id=\"img\" src=\"" withString:@""];
        url = [url stringByReplacingOccurrencesOfString:@"\" style=\"" withString:@""];
        NSString *x = json[@"x"];
        NSString *y = json[@"y"];
        if (url.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(QJHenTaiParserStatusSuccess,url,x,y);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(QJHenTaiParserStatusParseFail,nil,nil,nil);
            });
        }
    }];
    [task resume];
}

#pragma mark -评星
- (void)updateStarWithGid:(NSString *)gid token:(NSString *)token apikey:(NSString *)apikey apiuid:(NSString *)apiuid rating:(NSInteger)rating complete:(LoginHandler)completion {
    NetworkShow();
    NSDictionary *jsonDictionary = @{
                                     @"method": @"rategallery",
                                     @"gid": gid,
                                     @"apikey": apikey,
                                     @"apiuid": apiuid,
                                     @"rating": @(rating),
                                     @"token": token
                                     };
    NSString *apiurl = [NSObjForKey(@"ExHentaiStatus") boolValue] ? EXHENTAI_APIURL : HENTAI_APIURL;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:apiurl]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:jsonDictionary options:NSJSONWritingPrettyPrinted error:nil];
    NSURLSessionTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NetworkHidden();
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"网络有点小问题呢...");
                completion(QJHenTaiParserStatusNetworkFail);
            });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        if (json.allKeys.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastSuccess(nil, @"评定成功!");
                completion(QJHenTaiParserStatusSuccess);
            });
        }
    }];
    [task resume];
}

#pragma mark -种子爬取
- (void)updateTorrentInfoWithGid:(NSString *)gid token:(NSString *)token complete:(TorrentListHandler)completion {
    NetworkShow();
    NSString *url = [NSString stringWithFormat:@"gallerytorrents.php?gid=%@&t=%@",gid,token];
    NSMutableString *finalUrl = [NSMutableString stringWithString:[NSObjForKey(@"ExHentaiStatus") boolValue] ? EXHENTAI_URL : HENTAI_URL];
    [finalUrl appendString:url];
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:[NSURL URLWithString:finalUrl] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NetworkHidden();
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ToastError(nil, @"网络有点小问题呢...");
                completion(QJHenTaiParserStatusNetworkFail, nil);
            });
            return;
        }
        TFHpple *xpathParser = [[TFHpple alloc] initWithHTMLData:data];
        //NSLog(@"%@",[[NSString alloc] initWithData:data  encoding:NSUTF8StringEncoding]);
        NSArray *torrents  = [xpathParser searchWithXPathQuery:@"//form [@method='post']//table"];
        if (nil == torrents) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(QJHenTaiParserStatusParseFail,nil);
            });
            return;
        }
        NSMutableArray *newTorrents = [NSMutableArray new];
        for (TFHppleElement *subElement in torrents) {
            QJTorrentItem *item = [QJTorrentItem new];
            item.posted = [[subElement searchWithXPathQuery:@"//td"].firstObject text];
            item.size = [[subElement searchWithXPathQuery:@"//td"][1] text];
            item.seeds = [[subElement searchWithXPathQuery:@"//td"][3] text];
            item.peers = [[subElement searchWithXPathQuery:@"//td"][4] text];
            item.downloads = [[subElement searchWithXPathQuery:@"//td"][5] text];
            item.uploader = [[subElement searchWithXPathQuery:@"//td"][6] text];
            item.name = [[subElement searchWithXPathQuery:@"//td//a"].firstObject text];
            NSString *url = [subElement searchWithXPathQuery:@"//td//a"].firstObject[@"href"];
            item.magnet = [NSString stringWithFormat:@"magnet:?xt=urn:btih:%@",[[url componentsSeparatedByString:@"/"].lastObject stringByDeletingPathExtension]];
            [newTorrents addObject:item];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(QJHenTaiParserStatusSuccess,newTorrents);
        });
        
    }];
    [task resume];
}

#pragma mark -懒加载
- (NSURLSession *)session {
    if (!_session) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.HTTPShouldSetCookies = YES;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return _session;
}

- (NSArray<NSString *> *)classifyArr {
    if (!_classifyArr) {
        _classifyArr = @[@"DOUJINSHI",
                         @"MANGA",
                         @"ARTIST CG",
                         @"GAME CG",
                         @"WESTERN",
                         @"NON-H",
                         @"IMAGE SET",
                         @"COSPLAY",
                         @"ASIAN PORN",
                         @"MISC"];
    }
    return _classifyArr;
}

- (NSArray<UIColor *> *)colorArr {
    if (nil == _colorArr) {
        _colorArr = @[
                      DOUJINSHI_COLOR,
                      MANGA_COLOR,
                      ARTISTCG_COLOR,
                      GAMECG_COLOR,
                      WESTERN_COLOR,
                      NONH_COLOR,
                      IMAGESET_COLOR,
                      COSPLAY_COLOR,
                      ASIANPORN_COLOR,
                      MISC_COLOR
                      ];
    }
    return _colorArr;
}

@end
