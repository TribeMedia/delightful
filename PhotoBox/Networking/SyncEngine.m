//
//  SyncEngine.m
//  Delightful
//
//  Created by  on 10/13/14.
//  Copyright (c) 2014 Touches. All rights reserved.
//

#import "SyncEngine.h"

#import "PhotoBoxClient.h"

#import "DLFDatabaseManager.h"

#import "Photo.h"

#import "Album.h"

#import "Tag.h"

#import <YapDatabase.h>

#define FETCHING_PAGE_SIZE 100

#define DEFAULT_PHOTOS_SORT @"dateUploaded,desc"

NSString *const SyncEngineWillStartFetchingNotification = @"com.getdelightfulapp.SyncEngineWillStartFetchingNotification";
NSString *const SyncEngineDidFinishFetchingNotification = @"com.getdelightfulapp.SyncEngineDidFinishFetchingNotification";
NSString *const SyncEngineDidFailFetchingNotification = @"com.getdelightfulapp.SyncEngineDidFailFetchingNotification";

NSString *const SyncEngineNotificationResourceKey = @"resource";
NSString *const SyncEngineNotificationIdentifierKey = @"identifier";
NSString *const SyncEngineNotificationPageKey = @"page";
NSString *const SyncEngineNotificationErrorKey = @"error";
NSString *const SyncEngineNotificationCountKey = @"count";

@interface SyncPhotosParam : NSObject

@property (nonatomic, assign) BOOL isSyncing;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, assign) int photosFetchingPage;
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, assign) BOOL refreshRequested;
@property (nonatomic, strong) NSString *sort;
@property (nonatomic) Class collectionType;

@end

@implementation SyncPhotosParam
@end

@interface SyncEngine ()

@property (nonatomic, strong) YapDatabase *database;

@property (nonatomic, strong) YapDatabaseConnection *photosConnection;

@property (nonatomic, strong) YapDatabaseConnection *albumsConnection;

@property (nonatomic, strong) YapDatabaseConnection *tagsConnection;

@property (nonatomic, assign) int albumsFetchingPage;

@property (nonatomic, assign) int photosFetchingPage;

@property (nonatomic, assign) BOOL tagsRefreshRequested;

@property (nonatomic, assign) BOOL albumsRefreshRequested;

@property (nonatomic, assign) BOOL photosRefreshRequested;

@property (nonatomic, assign) BOOL isSyncingPhotos;
@property (nonatomic, assign) BOOL isSyncingAlbums;
@property (nonatomic, assign) BOOL isSyncingTags;

@property (nonatomic, strong) NSMutableDictionary *syncingJobs;

@end

@implementation SyncEngine

+ (instancetype)sharedEngine {
    static id _sharedEngine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedEngine = [[self alloc] init];
    });
    
    return _sharedEngine;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.database = [[DLFDatabaseManager manager] currentDatabase];
        
        self.photosConnection = [self.database newConnection];
        self.photosConnection.objectCacheEnabled = NO; // don't need cache for write-only connection
        self.photosConnection.metadataCacheEnabled = NO;
        
        self.albumsConnection = [self.database newConnection];
        self.albumsConnection.objectCacheEnabled = NO; // don't need cache for write-only connection
        self.albumsConnection.metadataCacheEnabled = NO;
        
        self.tagsConnection = [self.database newConnection];
        self.tagsConnection.objectCacheEnabled = NO; // don't needpa cache for write-only connection
        self.tagsConnection.metadataCacheEnabled = NO;
        
        self.syncingJobs = [NSMutableDictionary dictionary];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)startSyncingPhotos {
    if (!self.isSyncingPhotos) {
        [self fetchPhotosForPage:0 sort:self.photosSyncSort?:DEFAULT_PHOTOS_SORT];
    }
}

- (void)startSyncingAlbums {
    if (!self.isSyncingAlbums) {
        [self fetchAlbumsForPage:1];
    }
}

- (void)startSyncingTags {
    if (!self.isSyncingTags) {
        [self fetchTagsForPage:1];
    }
}

- (void)startSyncingPhotosInCollection:(NSString *)collection collectionType:(Class)collectionType sort:(NSString *)sort {
    if (![self isSyncingPhotosInCollectionWithIdentifier:collection]) {
        if (collectionType == Album.class) {
            [self fetchPhotosInAlbum:collection page:0 sort:sort];
        } else if (collectionType == Tag.class) {
            [self fetchPhotosInTag:collection page:0 sort:sort];
        }
    }
}

- (void)refreshResource:(NSString *)resource {
    if ([resource isEqualToString:NSStringFromClass([Tag class])]) {
        self.tagsRefreshRequested = (!self.isSyncingTags)?YES:NO;
    } else if ([resource isEqualToString:NSStringFromClass([Album class])]) {
        self.albumsRefreshRequested = (!self.isSyncingAlbums)?YES:NO;
    } else if ([resource isEqualToString:NSStringFromClass([Photo class])]) {
        self.photosRefreshRequested = !(self.isSyncingPhotos)?YES:NO;
    }
}

- (void)setPausePhotosSync:(BOOL)pausePhotosSync {
    _pausePhotosSync = pausePhotosSync;
    
    if (!_pausePhotosSync) {
        [self fetchPhotosForPage:self.photosFetchingPage sort:(self.photosSyncSort)?:DEFAULT_PHOTOS_SORT];
    }
}

- (void)fetchTagsForPage:(int)page {
    CLS_LOG(@"Fetching tags page %d", page);
    [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineWillStartFetchingNotification object:nil userInfo:@{SyncEngineNotificationResourceKey: NSStringFromClass([Tag class]), SyncEngineNotificationPageKey: @(page)}];
    self.isSyncingTags = YES;
    
    [[PhotoBoxClient sharedClient] getTagsForPage:page pageSize:0 success:^(NSArray *tags) {
        CLS_LOG(@"Did finish fetching %d tags page %d", (int)tags.count, page);
        if (tags.count > 0) {
            [self.tagsConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                for (Tag *tag in tags) {
                    [transaction setObject:tag forKey:tag.tagId inCollection:tagsCollectionName];
                }
            } completionBlock:^{
                CLS_LOG(@"Done inserting tags to db");
            }];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFinishFetchingNotification object:nil userInfo:@{SyncEngineNotificationResourceKey: NSStringFromClass([Tag class]), SyncEngineNotificationPageKey: @(page), SyncEngineNotificationCountKey: @(tags.count)}];
        self.isSyncingTags = NO;
        
        if (self.tagsRefreshRequested) {
            self.tagsRefreshRequested = NO;
            [self fetchTagsForPage:0];
        }
    } failure:^(NSError *error) {
        CLS_LOG(@"Error fetching tags page %d: %@", page, error);
        self.isSyncingTags = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFailFetchingNotification object:nil userInfo:@{SyncEngineNotificationErrorKey: error, SyncEngineNotificationResourceKey: NSStringFromClass([Tag class]), SyncEngineNotificationPageKey: @(page)}];
    }];
}

- (void)fetchAlbumsForPage:(int)page {
    CLS_LOG(@"Fetching albums page %d", page);
    self.isSyncingAlbums = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineWillStartFetchingNotification object:nil userInfo:@{SyncEngineNotificationResourceKey: NSStringFromClass([Album class]), SyncEngineNotificationPageKey: @(page)}];
    
    [[PhotoBoxClient sharedClient] getAlbumsForPage:page pageSize:FETCHING_PAGE_SIZE success:^(NSArray *albums) {
        CLS_LOG(@"Did finish fetching %d albums page %d", (int)albums.count, page);
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFinishFetchingNotification object:nil userInfo:@{SyncEngineNotificationResourceKey: NSStringFromClass([Album class]), SyncEngineNotificationPageKey: @(page), SyncEngineNotificationCountKey: @(albums.count)}];
        
        if (albums.count > 0) {
            [self.albumsConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                for (Album *album in albums) {
                    [transaction setObject:album forKey:album.albumId inCollection:albumsCollectionName];
                }
            } completionBlock:^{
                CLS_LOG(@"Done inserting albums to db page %d", page);
                
                if (self.albumsRefreshRequested) {
                    self.albumsRefreshRequested = NO;
                    [self fetchAlbumsForPage:1];
                } else {
                    if (self.pauseAlbumsSync) {
                        self.albumsFetchingPage = page;
                    } else {
                        [self fetchAlbumsForPage:page+1];
                    }
                }
            }];
        } else {
            self.isSyncingAlbums = NO;
            self.albumsFetchingPage = 0;
        }
    } failure:^(NSError *error) {
        CLS_LOG(@"Error fetching albums page %d: %@", page, error);
        self.isSyncingAlbums = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFailFetchingNotification object:nil userInfo:@{SyncEngineNotificationErrorKey: error, SyncEngineNotificationResourceKey: NSStringFromClass([Album class]), SyncEngineNotificationPageKey: @(page)}];
        self.albumsFetchingPage = page;
    }];
}

- (void)fetchPhotosForPage:(int)page sort:(NSString *)sort{
    CLS_LOG(@"Fetching photos for page %d", page);
    self.isSyncingPhotos = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineWillStartFetchingNotification object:nil userInfo:@{SyncEngineNotificationResourceKey: NSStringFromClass([Photo class]), SyncEngineNotificationPageKey: @(page)}];
    
    [[PhotoBoxClient sharedClient] getPhotosForPage:page sort:sort pageSize:FETCHING_PAGE_SIZE success:^(NSArray *photos) {
        CLS_LOG(@"Did finish fetching %d photos page %d", (int)photos.count, page);
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFinishFetchingNotification object:nil userInfo:@{SyncEngineNotificationResourceKey: NSStringFromClass([Photo class]), SyncEngineNotificationPageKey: @(page), SyncEngineNotificationCountKey: @(photos.count)}];
        
        if (photos.count > 0) {
            [self insertPhotos:photos completion:^{
                CLS_LOG(@"Done inserting photos to db page %d", page);
                
                if (self.photosRefreshRequested) {
                    self.photosRefreshRequested = NO;
                    [self fetchPhotosForPage:0 sort:self.photosSyncSort?:sort];
                } else {
                    if (self.pausePhotosSync) {
                        CLS_LOG(@"Pausing photos sync");
                        self.photosFetchingPage = page;
                        self.isSyncingPhotos = NO;
                    } else {
                        [self fetchPhotosForPage:page+1 sort:sort];
                    }
                }
            }];
        } else {
            self.isSyncingPhotos = NO;
            self.photosFetchingPage = 0;
        }
    } failure:^(NSError *error) {
        CLS_LOG(@"Error fetching photos page %d: %@", page, error);
        self.isSyncingPhotos = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFailFetchingNotification object:nil userInfo:@{SyncEngineNotificationErrorKey: error, SyncEngineNotificationResourceKey: NSStringFromClass([Photo class]), SyncEngineNotificationPageKey: @(page)}];
        self.photosFetchingPage = page;
    }];
}

- (void)fetchPhotosInTag:(NSString *)tag page:(int)page sort:(NSString *)sort {
    [self setIsSyncing:YES photosInCollection:tag collectionType:Tag.class page:page sort:sort];
    
    [[PhotoBoxClient sharedClient] getPhotosInTag:tag sort:sort page:page pageSize:FETCHING_PAGE_SIZE success:^(NSArray *photos) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFinishFetchingNotification object:nil userInfo:@{SyncEngineNotificationResourceKey: NSStringFromClass([Photo class]), SyncEngineNotificationPageKey: @(page), SyncEngineNotificationCountKey: @(photos.count), SyncEngineNotificationIdentifierKey:tag}];
        
        if (photos.count > 0) {
            [self insertPhotos:photos completion:^{
                CLS_LOG(@"Done inserting photos to db page %d in tag %@", page, tag);
                
                if ([self isRefreshRequestedForCollection:tag]) {
                    [self setRefreshRequested:NO collection:tag];
                    SyncPhotosParam *param = [self.syncingJobs objectForKey:tag];
                    [self fetchPhotosInTag:tag page:0 sort:param.sort];
                } else {
                    if ([self isPausedForCollection:tag]) {
                        CLS_LOG(@"Pausing photos sync");
                        SyncPhotosParam *param = [self.syncingJobs objectForKey:tag];
                        param.isSyncing = NO;
                        param.photosFetchingPage = page;
                        [self.syncingJobs setObject:param forKey:tag];
                    } else {
                        [self fetchPhotosInTag:tag page:page+1 sort:sort];
                    }
                }
            }];
        }
    } failure:^(NSError *error) {
        [self setIsSyncing:NO photosInCollection:tag collectionType:Tag.class page:page sort:sort];
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFailFetchingNotification object:nil userInfo:@{SyncEngineNotificationErrorKey: error, SyncEngineNotificationResourceKey: NSStringFromClass([Photo class]), SyncEngineNotificationIdentifierKey:tag, SyncEngineNotificationPageKey: @(page)}];
    }];
}

- (void)fetchPhotosInAlbum:(NSString *)album page:(int)page sort:(NSString *)sort {
    [self setIsSyncing:YES photosInCollection:album collectionType:Album.class page:page sort:sort];
    
    [[PhotoBoxClient sharedClient] getPhotosInAlbum:album sort:sort page:page pageSize:FETCHING_PAGE_SIZE success:^(NSArray *photos) {
        CLS_LOG(@"Did finish fetching %d photos page %d in album %@", (int)photos.count, page, album);
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFinishFetchingNotification object:nil userInfo:@{SyncEngineNotificationResourceKey: NSStringFromClass([Photo class]), SyncEngineNotificationPageKey: @(page), SyncEngineNotificationCountKey: @(photos.count), SyncEngineNotificationIdentifierKey:album}];
        if (photos.count > 0) {
            [self insertPhotos:photos completion:^{
                CLS_LOG(@"Done inserting photos to db page %d in album %@", page, album);
                
                if ([self isRefreshRequestedForCollection:album]) {
                    [self setRefreshRequested:NO collection:album];
                    SyncPhotosParam *param = [self.syncingJobs objectForKey:album];
                    [self fetchPhotosInAlbum:album page:0 sort:param.sort];
                } else {
                    if ([self isPausedForCollection:album]) {
                        CLS_LOG(@"Pausing photos sync");
                        SyncPhotosParam *param = [self.syncingJobs objectForKey:album];
                        param.isSyncing = NO;
                        param.photosFetchingPage = page;
                        [self.syncingJobs setObject:param forKey:album];
                    } else {
                        [self fetchPhotosInAlbum:album page:page+1 sort:sort];
                    }
                }
            }];
        } else {
            [self setIsSyncing:NO photosInCollection:album collectionType:Album.class page:page sort:sort];
            [self setPhotosFetchingPage:0 photosInCollection:album];
        }
    } failure:^(NSError *error) {
        [self setIsSyncing:NO photosInCollection:album collectionType:Album.class page:page sort:sort];
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineDidFailFetchingNotification object:nil userInfo:@{SyncEngineNotificationErrorKey: error, SyncEngineNotificationResourceKey: NSStringFromClass([Photo class]), SyncEngineNotificationIdentifierKey:album, SyncEngineNotificationPageKey: @(page)}];
    }];
}

- (void)setRefreshRequested:(BOOL)refreshRequested collection:(NSString *)collectionIdentifier {
    SyncPhotosParam *param = [self.syncingJobs objectForKey:collectionIdentifier];
    if (!param) {
        param = [[SyncPhotosParam alloc] init];
        [param setIdentifier:collectionIdentifier];
    }
    [param setRefreshRequested:refreshRequested];
    [self.syncingJobs setObject:param forKey:collectionIdentifier];
}

- (BOOL)isRefreshRequestedForCollection:(NSString *)collectionIdentifier {
    SyncPhotosParam *param = [self.syncingJobs objectForKey:collectionIdentifier];
    if (!param) {
        return NO;
    }
    return param.refreshRequested;
}

- (void)setIsPaused:(BOOL)pause collection:(NSString *)collectionIdentifier {
    SyncPhotosParam *param = [self.syncingJobs objectForKey:collectionIdentifier];
    if (!param) {
        param = [[SyncPhotosParam alloc] init];
        [param setIdentifier:collectionIdentifier];
    }
    [param setIsPaused:pause];
    [self.syncingJobs setObject:param forKey:collectionIdentifier];
}

- (BOOL)isPausedForCollection:(NSString *)collectionIdentifier {
    SyncPhotosParam *param = [self.syncingJobs objectForKey:collectionIdentifier];
    if (!param) {
        return NO;
    }
    return param.isPaused;
}

- (void)setIsSyncing:(BOOL)isSyncing photosInCollection:(NSString *)collectionIdentifier collectionType:(Class)collectionType page:(int)page sort:(NSString *)sort {
    if (isSyncing) {
        SyncPhotosParam *param = [[SyncPhotosParam alloc] init];
        [param setIdentifier:collectionIdentifier];
        [param setIsSyncing:YES];
        [param setCollectionType:collectionType];
        [param setSort:sort];
        [param setPhotosFetchingPage:page];
        [self.syncingJobs setObject:param forKey:collectionIdentifier];
    } else {
        SyncPhotosParam *param = [self.syncingJobs objectForKey:collectionIdentifier];
        if (param) {
            [param setIsSyncing:NO];
            [param setPhotosFetchingPage:page];
            [self.syncingJobs setObject:param forKey:collectionIdentifier];
        }
    }
}

- (BOOL)isSyncingPhotosInCollectionWithIdentifier:(NSString *)identifier {
    SyncPhotosParam *param = [self.syncingJobs objectForKey:identifier];
    if (!param) {
        return NO;
    }
    
    return param.isSyncing;
}

- (void)setPhotosFetchingPage:(int)photosFetchingPage photosInCollection:(NSString *)collectionIdentifier {
    SyncPhotosParam *param = [self.syncingJobs objectForKey:collectionIdentifier];
    if (!param) {
        param = [[SyncPhotosParam alloc] init];
    }
    param.photosFetchingPage = photosFetchingPage;
    [self.syncingJobs setObject:param forKey:collectionIdentifier];
}

- (int)photosFetchingPageForIdentifier:(NSString *)collectionIdentifier {
    SyncPhotosParam *param = [self.syncingJobs objectForKey:collectionIdentifier];
    if (!param) {
        return 0;
    }
    
    return param.photosFetchingPage;
}

- (void)pauseSyncingPhotos:(BOOL)pause collection:(NSString *)collection {
    [self setIsPaused:pause collection:collection];
    
    if (!pause) {
        SyncPhotosParam *param = [self.syncingJobs objectForKey:collection];
        if (![self isSyncingPhotosInCollectionWithIdentifier:collection]) {
            if (param.collectionType == Album.class) {
                [self fetchPhotosInAlbum:param.identifier page:param.photosFetchingPage sort:param.sort];
            } else if (param.collectionType == Tag.class) {
                [self fetchPhotosInTag:param.identifier page:param.photosFetchingPage sort:param.sort];
            }
        }
        
    }
}

- (void)refreshPhotosInCollection:(NSString *)collection collectionType:(Class)collectionType sort:(NSString *)sort {
    [self setRefreshRequested:YES collection:collection];
    
    if (![self isSyncingPhotosInCollectionWithIdentifier:collection]) {
        if (collectionType == Album.class) {
            [self fetchPhotosInAlbum:collection page:0 sort:sort];
        } else if (collectionType == Tag.class) {
            [self fetchPhotosInTag:collection page:0 sort:sort];
        }
    }
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    CLS_LOG(@"did receive memory warning");
    self.pausePhotosSync = YES;
}

- (void)insertPhotos:(NSArray *)photos completion:(void(^)())completionBlock {
    [self.photosConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (Photo *photo in photos) {
            [transaction setObject:photo forKey:photo.photoId inCollection:photosCollectionName];
            
        }
    } completionBlock:completionBlock];
}

@end