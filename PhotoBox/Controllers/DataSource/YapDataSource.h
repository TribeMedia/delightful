//
//  YapDataSource.h
//  Delightful
//
//  Created by  on 9/28/14.
//  Copyright (c) 2014 Touches. All rights reserved.
//

#import "CollectionViewDataSource.h"

#import <YapDatabase.h>
#import <YapDatabaseView.h>

@class DLFYapDatabaseViewAndMapping;

@interface YapDataSource : CollectionViewDataSource

@property (nonatomic, strong) DLFYapDatabaseViewAndMapping *selectedViewMapping;
@property (nonatomic, strong) YapDatabaseConnection *mainConnection;
@property (nonatomic, strong) YapDatabaseConnection *bgConnection;
@property (nonatomic, strong) YapDatabase *database;

- (void)setupDatabase;

@end
