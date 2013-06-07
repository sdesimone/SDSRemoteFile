/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDSFileDownloader.h"
#import "SDWebImageOperation.h"

@interface SDSFileDownloaderOperation : NSOperation <SDWebImageOperation>

@property (strong, nonatomic, readonly) NSURLRequest *request;
@property (assign, nonatomic, readonly) SDSFileDownloaderOptions options;

- (id)initWithRequest:(NSURLRequest *)request
              options:(SDSFileDownloaderOptions)options
             progress:(SDSFileDownloaderProgressBlock)progressBlock
            completed:(SDSFileDownloaderCompletedBlock)completedBlock
            cancelled:(void (^)())cancelBlock;

@end
