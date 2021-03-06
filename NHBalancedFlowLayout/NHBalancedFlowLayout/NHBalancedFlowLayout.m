//
//  BalancedFlowLayout.m
//  BalancedFlowLayout
//
//  Created by Niels de Hoog on 31/10/13.
//  Copyright (c) 2013 Niels de Hoog. All rights reserved.
//

#import "NHBalancedFlowLayout.h"
#import "NHLinearPartition.h"

@interface NHBalancedFlowLayout ()
{
    CGRect **_itemFrameSections;
    NSInteger _numberOfItemFrameSections;
}

@property (nonatomic) CGSize contentSize;

@property (nonatomic, strong) NSArray *headerFrames;
@property (nonatomic, strong) NSArray *footerFrames;
@property (nonatomic, strong) NSMutableDictionary *preferredSizesForItemAtIndexPath;
@property (nonatomic, assign) NSInteger totalNumberOfItems;

@end

@implementation NHBalancedFlowLayout

#pragma mark - Lifecycle

- (void)clearItemFrames
{
    // free all item frame arrays
    if (NULL != _itemFrameSections) {
        for (NSInteger i = 0; i < _numberOfItemFrameSections; i++) {
            CGRect *frames = _itemFrameSections[i];
            free(frames);
        }
        
        free(_itemFrameSections);
        _itemFrameSections = NULL;
        [_preferredSizesForItemAtIndexPath removeAllObjects];
    }
}

- (void)dealloc
{
    [self clearItemFrames];
}

- (id)init
{
    self = [super init];
    if (self) {
        [self initialize];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initialize];
    }
    
    return self;
}

- (void)initialize
{
    // set to NULL so it is not released by accident in dealloc
    _itemFrameSections = NULL;
    _totalNumberOfItems =  -1;
    _preferredSizesForItemAtIndexPath = [NSMutableDictionary dictionary];
    
    self.sectionInset = UIEdgeInsetsMake(10, 10, 10, 10);
    self.minimumLineSpacing = 10;
    self.minimumInteritemSpacing = 10;
    self.headerReferenceSize = CGSizeMake(self.collectionView.frame.size.width, 44);
    self.footerReferenceSize = CGSizeZero;
    self.scrollDirection = UICollectionViewScrollDirectionVertical;
}

#pragma mark - Layout

- (void)prepareLayout
{
    [super prepareLayout];
    
    int numSections = (int)[self.collectionView numberOfSections];
    int total = 0;
    for (int i = 0; i< numSections; i++) {
        total += [self.collectionView numberOfItemsInSection:i];
    }
    
    if (total == self.totalNumberOfItems && self.headerFrames.count == numSections) {
        if (!self.forceInvalidate ) {
            return;
        }
    }
    
    self.totalNumberOfItems = total;
    
    NSAssert([self.delegate conformsToProtocol:@protocol(NHBalancedFlowLayoutDelegate)], @"UICollectionView delegate should conform to BalancedFlowLayout protocol");
        
    CGFloat idealHeight = self.preferredRowSize;
    if (idealHeight == 0) {
        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            idealHeight = CGRectGetHeight(self.collectionView.bounds) / 3.0;
        }
        else {
            idealHeight = CGRectGetWidth(self.collectionView.bounds) / 3.0;
        }
    }
    
    NSMutableArray *headerFrames = [NSMutableArray array];
    NSMutableArray *footerFrames = [NSMutableArray array];

    CGSize contentSize = CGSizeZero;
    
    // first release old item frame sectionspo
    [self clearItemFrames];
    
    // create new item frame sections
    _numberOfItemFrameSections = [self.collectionView numberOfSections];
    _itemFrameSections = (CGRect **)malloc(sizeof(CGRect *) * _numberOfItemFrameSections);
    
    for (int section = 0; section < [self.collectionView numberOfSections]; section++) {
        // add new item frames array to sections array
        NSInteger numberOfItemsInSections = [self.collectionView numberOfItemsInSection:section];
        CGRect *itemFrames = (CGRect *)malloc(sizeof(CGRect) * numberOfItemsInSections);
        _itemFrameSections[section] = itemFrames;
        
        CGSize headerSize = [self referenceSizeForHeaderInSection:section];
        CGSize sectionSize = CGSizeZero;
        
        CGRect headerFrame;
        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            headerFrame = CGRectMake(0, contentSize.height, CGRectGetWidth(self.collectionView.bounds), headerSize.height);
        } else {
            headerFrame = CGRectMake(contentSize.width, 0, headerSize.width, CGRectGetHeight(self.collectionView.bounds));
        }
        [headerFrames addObject:[NSValue valueWithCGRect:headerFrame]];
        
        CGFloat totalItemSize = [self totalItemSizeForSection:section preferredRowSize:idealHeight];
        NSInteger numberOfRows = MAX(roundf(totalItemSize / [self viewPortAvailableSize]), 1);
    
        CGPoint sectionOffset;
        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            sectionOffset = CGPointMake(0, contentSize.height + headerSize.height);
        } else {
            sectionOffset = CGPointMake(contentSize.width + headerSize.width, 0);
        }
        
        [self setFrames:itemFrames forItemsInSection:section numberOfRows:numberOfRows sectionOffset:sectionOffset sectionSize:&sectionSize];
        
        CGSize footerSize = [self referenceSizeForFooterInSection:section];
        CGRect footerFrame;
        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            footerFrame = CGRectMake(0, contentSize.height + headerSize.height + sectionSize.height, CGRectGetWidth(self.collectionView.bounds), footerSize.height);
        } else {
            footerFrame = CGRectMake(contentSize.width + headerSize.width + sectionSize.width, 0, footerSize.width, CGRectGetHeight(self.collectionView.bounds));
        }
        [footerFrames addObject:[NSValue valueWithCGRect:footerFrame]];

        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            contentSize = CGSizeMake(sectionSize.width, contentSize.height + headerSize.height + sectionSize.height + footerSize.height);
        }
        else {
            contentSize = CGSizeMake(contentSize.width + headerSize.width + sectionSize.width + footerSize.width, sectionSize.height);
        }
    }
    
    self.headerFrames = [headerFrames copy];
    self.footerFrames = [footerFrames copy];
    
    self.contentSize = contentSize;
}

- (CGSize)collectionViewContentSize
{
    return self.contentSize;
}

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSMutableArray *layoutAttributes = [NSMutableArray array];
    
    for (NSInteger section = 0, n = [self.collectionView numberOfSections]; section < n; section++) {
        NSIndexPath *sectionIndexPath = [NSIndexPath indexPathForItem:0 inSection:section];

        UICollectionViewLayoutAttributes *headerAttributes = [self layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                                                                                  atIndexPath:sectionIndexPath];
        if (! CGSizeEqualToSize(headerAttributes.frame.size, CGSizeZero) && CGRectIntersectsRect(headerAttributes.frame, rect)) {
            [layoutAttributes addObject:headerAttributes];
        }
            
        for (int i = 0; i < [self.collectionView numberOfItemsInSection:section]; i++) {
            CGRect itemFrame = _itemFrameSections[section][i];
            if (CGRectIntersectsRect(rect, itemFrame)) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:section];
                [layoutAttributes addObject:[self layoutAttributesForItemAtIndexPath:indexPath]];
            }
        }
        
        UICollectionViewLayoutAttributes *footerAttributes = [self layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                                                                                                  atIndexPath:sectionIndexPath];
        
        if (! CGSizeEqualToSize(footerAttributes.frame.size, CGSizeZero) && CGRectIntersectsRect(footerAttributes.frame, rect)) {
            [layoutAttributes addObject:footerAttributes];
        }
    }
    
    return layoutAttributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
    attributes.frame = [self itemFrameForIndexPath:indexPath];
    attributes.zIndex = 0;
    return attributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:kind withIndexPath:indexPath];
    
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        attributes.frame = [self headerFrameForSection:indexPath.section];
        [self adjustHeaderLayoutAttributes:attributes];
    } else if ([kind isEqualToString:UICollectionElementKindSectionFooter]) {
        attributes.frame = [self footerFrameForSection:indexPath.section];
    }
    return attributes;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds
{
    CGRect oldBounds = self.collectionView.bounds;
    if (CGRectGetWidth(newBounds) != CGRectGetWidth(oldBounds) || CGRectGetHeight(newBounds) != CGRectGetHeight(oldBounds)) {
        self.totalNumberOfItems = -1;
    }
    
    return YES;
}

- (CGPoint)targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset {
    if (self.targetIndexPath) {
        UICollectionViewLayoutAttributes *attr = [self layoutAttributesForItemAtIndexPath:self.targetIndexPath];
        self.targetIndexPath = nil;
        return CGPointMake(0, attr.frame.origin.y - self.collectionView.contentInset.top - self.minimumLineSpacing - self.minimumInteritemSpacing - self.sectionInset.top - self.headerReferenceSize.height);
    }
    
    return proposedContentOffset;
}

#pragma mark - Layout helpers

- (CGRect)headerFrameForSection:(NSInteger)section
{
    return [[self.headerFrames objectAtIndex:section] CGRectValue];
}

- (CGRect)itemFrameForIndexPath:(NSIndexPath *)indexPath
{
    return _itemFrameSections[indexPath.section][indexPath.item];
}

- (CGRect)footerFrameForSection:(NSInteger)section
{
    return [[self.footerFrames objectAtIndex:section] CGRectValue];
}

- (CGSize)preferredSizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGSize size;
    if (!self.preferredSizesForItemAtIndexPath[indexPath]) {
        size = [self.delegate collectionView:self.collectionView layout:self preferredSizeForItemAtIndexPath:indexPath];
        [self.preferredSizesForItemAtIndexPath setObject:[NSValue valueWithCGSize:size] forKey:indexPath];
    } else {
        size = [self.preferredSizesForItemAtIndexPath[indexPath] CGSizeValue];
    }
    
    return size;
}

- (CGFloat)totalItemSizeForSection:(NSInteger)section preferredRowSize:(CGFloat)preferredRowSize
{
    CGFloat totalItemSize = 0;
    for (NSInteger i = 0, n = [self.collectionView numberOfItemsInSection:section]; i < n; i++) {
        CGSize preferredSize = [self preferredSizeForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:section]];
        
        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            totalItemSize += (preferredSize.width / preferredSize.height) * preferredRowSize;
        }
        else {
            totalItemSize += (preferredSize.height / preferredSize.width) * preferredRowSize;
        }
    }
    
    return totalItemSize;
}

- (NSArray *)weightsForItemsInSection:(NSInteger)section
{
    NSMutableArray *weights = [NSMutableArray array];
    for (NSInteger i = 0, n = [self.collectionView numberOfItemsInSection:section]; i < n; i++) {
        CGSize preferredSize = [self preferredSizeForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:section]];
        NSInteger aspectRatio = self.scrollDirection == UICollectionViewScrollDirectionVertical ? roundf((preferredSize.width / preferredSize.height) * 100) : roundf((preferredSize.height / preferredSize.width) * 100);
        [weights addObject:@(aspectRatio)];
    }
    
    return [weights copy];
}

- (void)setFrames:(CGRect *)frames forItemsInSection:(NSInteger)section numberOfRows:(NSUInteger)numberOfRows sectionOffset:(CGPoint)sectionOffset sectionSize:(CGSize *)sectionSize
{
    NSArray *weights = [self weightsForItemsInSection:section];
    NSArray *partition = [NHLinearPartition linearPartitionForSequence:weights numberOfPartitions:numberOfRows];
    
    int i = 0;
    CGPoint offset = CGPointMake(sectionOffset.x + self.sectionInset.left, sectionOffset.y + self.sectionInset.top);
    CGFloat previousItemSize = 0;
    CGFloat contentMaxValueInScrollDirection = 0;
    for (NSArray *row in partition) {
        
        CGFloat summedRatios = 0;
        for (NSInteger j = i, n = i + [row count]; j < n; j++) {
            CGSize preferredSize = [self preferredSizeForItemAtIndexPath:[NSIndexPath indexPathForItem:j inSection:section]];
            
            if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
                summedRatios += preferredSize.width / preferredSize.height;
            }
            else {
                summedRatios += preferredSize.height / preferredSize.width;
            }
        }
        
        CGFloat rowSize = [self viewPortAvailableSize] - (([row count] - 1) * self.minimumInteritemSpacing);
        for (NSInteger j = i, n = i + [row count]; j < n; j++) {
            CGSize preferredSize = [self preferredSizeForItemAtIndexPath:[NSIndexPath indexPathForItem:j inSection:section]];
            
            CGSize actualSize = CGSizeZero;
            if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
                actualSize = CGSizeMake(roundf(rowSize / summedRatios * (preferredSize.width / preferredSize.height)), roundf(rowSize / summedRatios));
            }
            else {
                actualSize = CGSizeMake(roundf(rowSize / summedRatios), roundf(rowSize / summedRatios * (preferredSize.height / preferredSize.width)));
            }
            
            CGRect frame = CGRectMake(offset.x, offset.y, actualSize.width, actualSize.height);
            // copy frame into frames ptr and increment ptr
            *frames++ = frame;
            
            
            if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
                offset.x += actualSize.width + self.minimumInteritemSpacing;
                previousItemSize = actualSize.height;
                contentMaxValueInScrollDirection = CGRectGetMaxY(frame);
            }
            else {
                offset.y += actualSize.height + self.minimumInteritemSpacing;
                previousItemSize = actualSize.width;
                contentMaxValueInScrollDirection = CGRectGetMaxX(frame);
            }
        }
        
        /**
         * Check if row actually contains any items before changing offset,
         * because linear partitioning algorithm might return a row with no items.
         */
        if ([row count] > 0) {
            // move offset to next line
            if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
                offset = CGPointMake(self.sectionInset.left, offset.y + previousItemSize + self.minimumLineSpacing);
            }
            else {
                offset = CGPointMake(offset.x + previousItemSize + self.minimumLineSpacing, self.sectionInset.top);
            }
        }
        
        i += [row count];
    }
    
    if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
        *sectionSize = CGSizeMake([self viewPortWidth], (contentMaxValueInScrollDirection - sectionOffset.y) + self.sectionInset.bottom);
    }
    else {
        *sectionSize = CGSizeMake((contentMaxValueInScrollDirection - sectionOffset.x) + self.sectionInset.right, [self viewPortHeight]);
    }
}

- (CGFloat)viewPortWidth
{
    return CGRectGetWidth(self.collectionView.frame) - self.collectionView.contentInset.left - self.collectionView.contentInset.right;
}

- (CGFloat)viewPortHeight
{
    return (CGRectGetHeight(self.collectionView.frame) - self.collectionView.contentInset.top  - self.collectionView.contentInset.bottom);
}

- (CGFloat)viewPortAvailableSize
{
    CGFloat availableSize = 0;
    if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
        availableSize = [self viewPortWidth] - self.sectionInset.left - self.sectionInset.right;
    }
    else {
        availableSize = [self viewPortHeight] - self.sectionInset.top - self.sectionInset.bottom;
    }
    
    return availableSize;
}

#pragma mark - Custom setters

- (void)setPreferredRowSize:(CGFloat)preferredRowHeight
{
    _preferredRowSize = preferredRowHeight;
    
    [self invalidateLayout];
}

- (void)setSectionInset:(UIEdgeInsets)sectionInset
{
    _sectionInset = sectionInset;
    
    [self invalidateLayout];
}

- (void)setMinimumLineSpacing:(CGFloat)minimumLineSpacing
{
    _minimumLineSpacing = minimumLineSpacing;
    
    [self invalidateLayout];
}

- (void)setMinimumInteritemSpacing:(CGFloat)minimumInteritemSpacing
{
    _minimumInteritemSpacing = minimumInteritemSpacing;
    
    [self invalidateLayout];
}

- (void)setHeaderReferenceSize:(CGSize)headerReferenceSize
{
    _headerReferenceSize = headerReferenceSize;
    
    [self invalidateLayout];
}

- (void)setFooterReferenceSize:(CGSize)footerReferenceSize
{
    _footerReferenceSize = footerReferenceSize;
    
    [self invalidateLayout];
}

#pragma mark - Delegate

- (id<NHBalancedFlowLayoutDelegate>)delegate
{
    return (id<NHBalancedFlowLayoutDelegate>)self.collectionView.delegate;
}

#pragma mark - Delegate helpers

- (CGSize)referenceSizeForHeaderInSection:(NSInteger)section
{
    BOOL respondsToSelector = [self.collectionView.delegate respondsToSelector:@selector(collectionView:layout:referenceSizeForHeaderInSection:)];
    if (respondsToSelector) {
        return [(id <NHBalancedFlowLayoutDelegate>)self.collectionView.delegate collectionView:self.collectionView layout:self referenceSizeForHeaderInSection:section];
    }
    return self.headerReferenceSize;
}

- (CGSize)referenceSizeForFooterInSection:(NSInteger)section
{
    BOOL respondsToSelector = [self.collectionView.delegate respondsToSelector:@selector(collectionView:layout:referenceSizeForFooterInSection:)];
    if (respondsToSelector) {
        return [(id <NHBalancedFlowLayoutDelegate>)self.collectionView.delegate collectionView:self.collectionView layout:self referenceSizeForFooterInSection:section];
    }
    return self.footerReferenceSize;
}

- (void)adjustHeaderLayoutAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes {
    UICollectionView * const cv = self.collectionView;
    
    NSInteger numberOfSections = [cv numberOfSections];
    
    NSInteger section = layoutAttributes.indexPath.section;
    
    CGPoint const contentOffset = cv.contentOffset;
    
    if (section < numberOfSections) {
        // get number of items in the missing header section
        NSInteger numberOfItemsInSection = [cv numberOfItemsInSection:section];
        
        NSIndexPath *firstObjectIndexPath = [NSIndexPath indexPathForItem:0 inSection:section];
        NSIndexPath *lastObjectIndexPath = [NSIndexPath indexPathForItem:MAX(0, (numberOfItemsInSection - 1)) inSection:section];
        
        BOOL cellsExist;
        UICollectionViewLayoutAttributes *firstObjectAttrs;
        UICollectionViewLayoutAttributes *lastObjectAttrs;
        
        // get the first and last cell atributes
        if (numberOfItemsInSection > 0) { // use cell data if items exist
            cellsExist = YES;
            firstObjectAttrs = [self layoutAttributesForItemAtIndexPath:firstObjectIndexPath];
            lastObjectAttrs = [self layoutAttributesForItemAtIndexPath:lastObjectIndexPath];
        } else { // else use the header and footer
            cellsExist = NO;
            firstObjectAttrs = [self layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                                                    atIndexPath:firstObjectIndexPath];
            lastObjectAttrs = [self layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                                                                   atIndexPath:lastObjectIndexPath];
            
        }
        
        CGFloat topHeaderHeight = (cellsExist) ? CGRectGetHeight(layoutAttributes.frame) : 0;
        CGFloat bottomHeaderHeight = CGRectGetHeight(layoutAttributes.frame);
        CGRect frameWithEdgeInsets = UIEdgeInsetsInsetRect(layoutAttributes.frame, cv.contentInset);
        CGPoint origin = frameWithEdgeInsets.origin;
        
        /**
         
         there are three possibilities of header y origin:
         (1) when the section's first item hasn't reached the top of collection view => (CGRectGetMinY(firstObjectAttrs.frame) - topHeaderHeight)
         (2) when the section's first item has crossed the top of collection view, in this case the header should be on the top of collection view =>　contentOffset.y + cv.contentInset.top
         (3) when the section's last item has reached the top of collection view, in this case the header should follow along the last item's position => (CGRectGetMaxY(lastObjectAttrs.frame) - bottomHeaderHeight)
         **/
        origin.y = MIN(
                       MAX(
                           contentOffset.y + cv.contentInset.top,
                           (CGRectGetMinY(firstObjectAttrs.frame) - topHeaderHeight)
                           ),
                       (CGRectGetMaxY(lastObjectAttrs.frame) - bottomHeaderHeight)
                       );
        
        
        layoutAttributes.frame = (CGRect){
            .origin = origin,
            .size = layoutAttributes.frame.size
        };
    }
    
    layoutAttributes.zIndex = 100000;
}

@end
