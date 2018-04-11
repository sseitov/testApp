//
//  HLS_Converter.h
//  cryptoBox (MilCryptor Secure Platform)
//
//  Created by Denys Borysiuk on 20.03.2018.
//  Copyright © 2016 ArchiSec Solutions, Ltd. All rights reserved.//
//

#import <Foundation/Foundation.h>

typedef void(^HLS_ProgressBlock)(NSUInteger bytesRead);
typedef void(^HLS_CompletionBlock)(BOOL success);

@interface HLS_Info : NSObject

@property (retain, nonatomic) NSMutableDictionary* fileMeta;
@property (retain, nonatomic) NSMutableDictionary* videoMeta;
@property (retain, nonatomic) NSData* matrix;

@end

@interface HLS_Converter : NSObject

- (BOOL)open:(NSString*)inPath info:(HLS_Info*)info;
- (void)convertTo:(NSString*)outPath doSegments:(BOOL)doSegments progressBlock:(HLS_ProgressBlock)progressBlock completionBlock:(HLS_CompletionBlock)completionBlock;

@property (atomic) BOOL cancelOperation;
@property (retain, nonatomic) HLS_Info* info;

@end
