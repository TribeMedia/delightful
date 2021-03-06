//
//  PhotoBoxClient.m
//  PhotoBox
//
//  Created by Nico Prananta on 8/31/13.
//  Copyright (c) 2013 Touches. All rights reserved.
//

#import "PhotoBoxClient.h"

#import "ConnectionManager.h"
#import "PhotoBoxRequestOperation.h"
#import "FavoritesManager.h"
#import "Album.h"
#import "Photo.h"
#import "Tag.h"
#import "DLFAsset.h"

#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <OVCMultipartPart.h>

@interface AFOAuth1Client ()
- (NSString *)authorizationHeaderForMethod:(NSString *)method
                                      path:(NSString *)path
                                parameters:(NSDictionary *)parameters;
@end

@interface PhotoBoxClient ()

@property (nonatomic, strong) AFOAuth1Client *oauthClient;


@end

@implementation PhotoBoxClient

+ (PhotoBoxClient *)sharedClient {
    static PhotoBoxClient *_sharedClient = nil;
    static dispatch_once_t onceTokenn;
    dispatch_once(&onceTokenn, ^{
        _sharedClient = [[PhotoBoxClient alloc] initWithBaseURL:[[ConnectionManager sharedManager] baseURL] key:[[[ConnectionManager sharedManager] consumerToken] key] secret:[[[ConnectionManager sharedManager] consumerToken] secret]];
    });
    
    return _sharedClient;
}

- (id)initWithBaseURL:(NSURL *)url key:(NSString *)key secret:(NSString *)secret{
    if (!url) {
        url = [NSURL URLWithString:@"http://trovebox.com"];
    }
    self = [super initWithBaseURL:url];
    if (!self) {
        return nil;
    }
    
    _oauthClient = [[AFOAuth1Client alloc] initWithBaseURL:url key:key secret:secret];
    
    if ([[ConnectionManager sharedManager] isUserLoggedIn]) {
        [_oauthClient setAccessToken:[[ConnectionManager sharedManager] oauthToken]];
    }
    [self setParameterEncoding:AFFormURLParameterEncoding];
    [self registerHTTPOperationClass:[PhotoBoxRequestOperation class]];
    
    return self;
}

- (void)refreshConnectionParameters {
    [self setValue:[[ConnectionManager sharedManager] baseURL] forKey:@"baseURL"];
    [self setValue:[[[ConnectionManager sharedManager] consumerToken] key] forKey:@"key"];
    [self setValue:[[[ConnectionManager sharedManager] consumerToken] secret] forKey:@"secret"];
    [self setAccessToken:[[ConnectionManager sharedManager] oauthToken]];
}

- (void)loginIfNecessaryToConnect:(void(^)())connectionBlock{
    if ([[ConnectionManager sharedManager] isUserLoggedIn]) {
        connectionBlock();
    } else {
        [[ConnectionManager sharedManager] openLoginFromStoryboardWithIdentifier:@"loginViewController"];
    }
}

#pragma mark - Setter

- (void)setValue:(id)value forKey:(NSString *)key {
    [super setValue:value forKey:key];
    [self.oauthClient setValue:value forKey:key];
}

#pragma mark - Favorite

- (NSOperation *)addFavoritePhoto:(Photo *)photo success:(void (^)(id))successBlock failure:(void (^)(NSError *))failureBlock {
    return [self addFavoritePhotoWithId:photo.photoId success:successBlock failure:failureBlock];
}

- (NSOperation *)addFavoritePhotoWithId:(NSString *)photoId success:(void (^)(id))successBlock failure:(void (^)(NSError *))failureBlock {
    NSString *path = [NSString stringWithFormat:@"photo/%@/update.json", photoId];
    return [self POST:path parameters:@{@"tagsAdd": favoritesTagName} resultClass:[Photo class] resultKeyPath:@"result" completion:^(AFHTTPRequestOperation *operation, id responseObject, NSError *error) {
        if (error) {
            if (failureBlock) {
                failureBlock(error);
            }
        } else {
            if (successBlock) {
                successBlock(responseObject);
            }
        }
    }];
}

- (NSOperation *)removeFavoritePhoto:(Photo *)photo success:(void (^)(id))successBlock failure:(void (^)(NSError *))failureBlock {
    return [self removeFavoritePhotoWithId:photo.photoId success:successBlock failure:failureBlock];
}

- (NSOperation *)removeFavoritePhotoWithId:(NSString *)photo success:(void (^)(id))successBlock failure:(void (^)(NSError *))failureBlock {
    NSString *path = [NSString stringWithFormat:@"photo/%@/update.json", photo];
    return [self POST:path parameters:@{@"tagsRemove": favoritesTagName} resultClass:[Photo class] resultKeyPath:@"result" completion:^(AFHTTPRequestOperation *operation, id responseObject, NSError *error) {
        if (error) {
            if (failureBlock) {
                failureBlock(error);
            }
        } else {
            if (successBlock) {
                successBlock(responseObject);
            }
        }
    }];
}

#pragma mark - Share

- (void)fetchSharingTokenForPhotoWithId:(NSString *)photoId completionBlock:(void (^)(NSString *))completion {
    //CLS_LOG(@"Fetching sharing token");
    NSString *path = [NSString stringWithFormat: @"/token/photo/%@/create.json", photoId];
    [self postPath:path parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (responseObject) {
            NSDictionary *result = responseObject[@"result"];
            NSString *token = nil;
            if ([result isKindOfClass:[NSDictionary class]]){
                token = result[@"id"];
            }
            //CLS_LOG(@"Fetching sharing token succeed");
            completion(token);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        //CLS_LOG(@"Fetching sharing token failed: %@", error);
        completion(nil);
    }];
}

#pragma mark - Resource Fetch

- (NSOperation *)getPhotosForPage:(int)page
                    sort:(NSString *)sort
                pageSize:(int)pageSize
                 success:(void(^)(id object))successBlock
                 failure:(void(^)(NSError*))failureBlock {
    return [self getPhotosInAlbum:nil
                      sort:sort
                      page:page
                  pageSize:(int)pageSize
                   success:successBlock
                   failure:failureBlock];
}

- (NSOperation *)getAlbumsForPage:(int)page
                pageSize:(int)pageSize
                 success:(void (^)(id))successBlock
                 failure:(void (^)(NSError *))failureBlock {
    __block NSOperation *operation;
    [self loginIfNecessaryToConnect:^{
        operation = [self GET:[NSString stringWithFormat:@"v1/albums/list.json?page=%d&pageSize=%d&%@",page, pageSize, [self photoSizesString]] parameters:nil resultClass:[Album class] resultKeyPath:@"result" success:successBlock failure:failureBlock];
    }];
    return operation;
}

- (NSOperation *)getTagsForPage:(int)page pageSize:(int)pageSize success:(void (^)(id))successBlock failure:(void (^)(NSError *))failureBlock {
    __block NSOperation *operation;
    [self loginIfNecessaryToConnect:^{
        operation = [self GET:[NSString stringWithFormat:@"v1/tags/list.json?page=%d&pageSize=%d",page, pageSize] parameters:nil resultClass:[Tag class] resultKeyPath:@"result" success:successBlock failure:failureBlock];
    }];
    return operation;
}

- (NSOperation *)getPhotosInAlbum:(NSString *)albumId
                    sort:(NSString *)sort
                    page:(int)page
                pageSize:(int)pageSize
                 success:(void (^)(id))successBlock
                 failure:(void (^)(NSError *))failureBlock {
    return [self getPhotosInResource:(albumId)?Album.class:Photo.class resourceId:albumId sort:sort page:page pageSize:pageSize success:successBlock failure:failureBlock];
}

- (NSOperation *)getPhotosInTag:(NSString *)tagId
                  sort:(NSString *)sort
                  page:(int)page
              pageSize:(int)pageSize
               success:(void(^)(id object))successBlock
               failure:(void(^)(NSError*))failureBlock {
    return [self getPhotosInResource:Tag.class resourceId:tagId sort:sort page:page pageSize:pageSize success:successBlock failure:failureBlock];
}

- (NSOperation *)getPhotosInResource:(Class)resourceClass resourceId:(NSString *)resourceId sort:(NSString *)sort page:(int)page pageSize:(int)pageSize success:(void (^)(id))successBlock failure:(void (^)(NSError *))failureBlock {
    NSString *resource = nil;
    if ([resourceClass isSubclassOfClass:Album.class]) {
        resource = [NSString stringWithFormat:@"&%@", [self albumsQueryString:resourceId]];
    } else if ([resourceClass isSubclassOfClass:Tag.class]) {
        resource = [NSString stringWithFormat:@"&%@", [self tagsQueryString:resourceId]];
    }
    
    if (!sort) {
        sort = [self sortByQueryString:@"dateTaken,DESC"];
        if ([resourceId isEqualToString:PBX_allAlbumIdentifier]){
            resource = @"";
            sort = [self sortByQueryString:@"dateUploaded,DESC"];
        }
    } else {
        sort = [self sortByQueryString:sort];
    }
    
    NSString *path = [NSString stringWithFormat:@"/v2/photos/list.json?page=%d&pageSize=%d&%@&%@", page, pageSize, sort, [self photoSizesString]];
    if (resource) {
        path = [path stringByAppendingString:resource];
    }
    
    __block NSOperation *operation;
    [self loginIfNecessaryToConnect:^{
        operation = [self GET:path parameters:nil resultClass:[Photo class] resultKeyPath:@"result" success:successBlock failure:failureBlock];
    }];
    
    return operation;
}

- (NSArray *)processResponseObject:(NSDictionary *)responseObject resourceClass:(Class)resource {
    NSArray *result = [responseObject objectForKey:@"result"];
    NSValueTransformer *transformer = [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:resource];
    return [transformer transformedValue:result];
}

- (OVCRequestOperation *)GET:(NSString *)path parameters:(NSDictionary *)parameters resultClass:(Class)resultClass resultKeyPath:(NSString *)keyPath success:(void (^)(id))successBlock failure:(void (^)(NSError *))failureBlock {
    return [self GET:path parameters:parameters resultClass:resultClass resultKeyPath:keyPath completion:^(AFHTTPRequestOperation *operation, id responseObject, NSError *error) {
        //CLS_LOG(@"Fetched responses");
        if (!error) {
            successBlock(responseObject);
        } else {
            if (operation.response.statusCode == 401) {
                [[ConnectionManager sharedManager] setIsGuestUser:YES];
            } else {
                failureBlock(error);
                return;
            }
            if ([[ConnectionManager sharedManager] isGuestUser]) {
                NSDictionary *userInfo = error.userInfo;
                if (userInfo) {
                    NSString *responseString = userInfo[NSLocalizedRecoverySuggestionErrorKey];
                    if (responseString) {
                        NSDictionary *responseObject = [NSJSONSerialization JSONObjectWithData:[responseString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                        if (responseObject) {
                            NSArray *results = responseObject[@"result"];
                            if (results) {
                                NSMutableArray *responseObjects = [NSMutableArray arrayWithCapacity:results.count];
                                for (NSDictionary *obj in results) {
                                    NSError *error;
                                    id transformedObj = [MTLJSONAdapter modelOfClass:resultClass fromJSONDictionary:obj error:&error];
                                    if (transformedObj) {
                                        [responseObjects addObject:transformedObj];
                                    }
                                }
                                if (successBlock) {
                                    successBlock(responseObjects);
                                    return;
                                }
                            }
                        }
                    }
                }
            }

        }
    }];
}

#pragma mark - Post

- (void)uploadAsset:(DLFAsset *)asset
           progress:(void(^)(float progress))progress
            success:(void(^)(id object))successBlock
            failure:(void(^)(NSError*))failureBlock {
    PHAsset *photo = asset.asset;
    [photo requestContentEditingInputWithOptions:nil completionHandler:^(PHContentEditingInput *contentEditingInput, NSDictionary *info) {
        NSString *tags = asset.tags;
        NSString *smartTags = [asset.smartTags componentsJoinedByString:@","];
        if (smartTags && smartTags.length > 0) {
            if (!tags) {
                tags = @"";
            }
            tags = [[tags stringByAppendingFormat:@", %@", smartTags] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]];
        }
        Album *album = asset.album;
        BOOL privatePhotos = asset.privatePhoto;
        NSString *fileName = contentEditingInput.fullSizeImageURL.lastPathComponent;
        PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
        [options setResizeMode:PHImageRequestOptionsResizeModeNone];
        [options setDeliveryMode:PHImageRequestOptionsDeliveryModeHighQualityFormat];
        [[PHImageManager defaultManager] requestImageDataForAsset:photo options:options resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
            CLLocation *location = photo.location;
            NSString *path = @"/photo/upload.json";
            NSMutableDictionary *params = [NSMutableDictionary dictionary];
            if (location) {
                [params addEntriesFromDictionary:@{@"latitude": [NSString stringWithFormat:@"%f", location.coordinate.latitude], @"longitude": [NSString stringWithFormat:@"%f", location.coordinate.longitude]}];
            }
            if (tags && tags.length > 0) {
                [params addEntriesFromDictionary:@{@"tags": tags}];
            }
            if (album) {
                [params addEntriesFromDictionary:@{@"albums": album.albumId}];
            }
            [params addEntriesFromDictionary:@{@"permission": (privatePhotos)?@"0":@"1"}];
            if (asset.photoTitle) {
                [params addEntriesFromDictionary:@{@"title":asset.photoTitle}];
            }
            if (asset.photoDescription) {
                [params addEntriesFromDictionary:@{@"description":asset.photoDescription}];
            }
            
            NSString *type = (__bridge NSString *)(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)(dataUTI), kUTTagClassMIMEType));
            
            OVCMultipartPart *part = [OVCMultipartPart partWithData:imageData name:@"photo" type:type filename:fileName];
            NSMutableURLRequest *request = [self multipartFormRequestWithMethod:@"POST" path:path parameters:params parts:@[part]];
            [request setValue:[self.oauthClient authorizationHeaderForMethod:request.HTTPMethod path:path parameters:params] forHTTPHeaderField:@"Authorization"];
            [request setHTTPShouldHandleCookies:NO];
            OVCRequestOperation *operation = [self HTTPRequestOperationWithRequest:request resultClass:[Photo class] resultKeyPath:@"result" completion:^(AFHTTPRequestOperation *operation, id responseObject, NSError *error) {
                if (error) {
                    if (failureBlock) {
                        failureBlock(error);
                    }
                } else {
                    if (successBlock) {
                        successBlock(responseObject);
                    }
                }
            }];
            if (progress) {
                [operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) {
                    float prog = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
                    progress(prog);
                }];
            }
            
            [self enqueueHTTPRequestOperation:operation];
        }];
    }];
}

#pragma mark - Getters

NSString *stringForPluralResourceType(ResourceType input) {
    NSArray *arr = @[
                     @"albums",
                     @"photos",
                     @"tags"
                     ];
    return (NSString *)[arr objectAtIndex:input];
}

NSString *stringForSingleResourceType(ResourceType input) {
    NSArray *arr = @[
                     @"albums",
                     @"photos",
                     @"tags"
                     ];
    return (NSString *)[arr objectAtIndex:input];
}

NSString *stringWithActionType(ActionType input) {
    NSArray *arr = @[
                     @"ListAction",
                     @"ViewAction",
                     @"UpdateAction",
                     @"DeleteAction",
                     @"CreateAction"
                     ];
    return (NSString *)[arr objectAtIndex:input];
}

- (NSString *)photoSizesString {
    NSArray *sizes = @[@"320x320",
                       @"640x640"
                       ];
    return AFQueryStringFromParametersWithEncoding(@{@"returnSizes": [sizes componentsJoinedByString:@","]}, NSUTF8StringEncoding);
}

- (NSString *)sortByQueryString:(NSString *)sortBy {
    return AFQueryStringFromParametersWithEncoding(@{@"sortBy": sortBy}, NSUTF8StringEncoding);
}

- (NSString *)albumsQueryString:(NSString *)album {
    return AFQueryStringFromParametersWithEncoding(@{@"album": album}, NSUTF8StringEncoding);
}

- (NSString *)tagsQueryString:(NSString *)tag {
    return AFQueryStringFromParametersWithEncoding(@{@"tags": tag}, NSUTF8StringEncoding);
}

#pragma mark - Oauth1Client

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters {
    return [self.oauthClient requestWithMethod:method path:path parameters:parameters];
}

- (void)acquireOAuthAccessTokenWithPath:(NSString *)path requestToken:(AFOAuth1Token *)requestToken accessMethod:(NSString *)accessMethod success:(void (^)(AFOAuth1Token *, id))success failure:(void (^)(NSError *))failure {
    [self.oauthClient acquireOAuthAccessTokenWithPath:path requestToken:requestToken accessMethod:accessMethod success:success failure:failure];
}

- (void)setAccessToken:(AFOAuth1Token *)accessToken {
    [self.oauthClient setAccessToken:accessToken];
}

- (void)setKey:(NSString *)key {
    [self.oauthClient setValue:key forKey:@"key"];
}

- (void)setSecret:(NSString *)secret {
    [self.oauthClient setValue:secret forKey:@"secret"];
}


@end
