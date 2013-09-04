//
//  NPImageView.h
//  NPRImageView
//
//  Created by Nico Prananta on 4/23/13.
//  Copyright (c) 2013 Touches. All rights reserved.
//

#import <UIKit/UIKit.h>

@class NPRImageView;

extern NSString * const NPRDidSetImageNotification;

@interface NPRDiskCache : NSObject
- (BOOL)imageExistsOnDiskWithKey:(NSString *)key;
@end

@interface NPRImageView : UIImageView

@property (nonatomic, assign) BOOL crossFade;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIActivityIndicatorView *indicatorView;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIImage *placeholderImage;
@property (nonatomic, strong) NSURL *imageContentURL;

@property (nonatomic, readonly) NPRDiskCache *sharedCache;
@property (nonatomic, strong) NSString *cacheKey;

@property (nonatomic, assign) BOOL shouldHideIndicatorView;

- (void)setImageWithContentsOfURL:(NSURL *)URL placeholderImage:(UIImage *)placeholderImage;

+ (UIImage *)originalImageForKey:(NSString *)key;

- (BOOL)isDownloadingImageAtURLString:(NSString *)urlString;
- (BOOL)hasDownloadedOriginalImageAtURL:(NSString *)url;

+ (void)printOperations;
+ (void)cancelAllOperations;

@end
