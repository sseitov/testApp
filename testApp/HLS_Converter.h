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

@interface HLS_Converter : NSObject

- (NSDictionary*)open:(NSString*)inPath;
- (BOOL)openWithInfo:(NSString*)inPath;
- (void)close;

- (void)convertTo:(NSString*)outPath
             info:(NSDictionary*)info
    progressBlock:(HLS_ProgressBlock)progressBlock
  completionBlock:(HLS_CompletionBlock)completionBlock;

@property (atomic) BOOL cancelOperation;

@end
