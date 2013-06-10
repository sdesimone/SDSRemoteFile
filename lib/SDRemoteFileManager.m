/*
 * This file is part of the SDSRemoteFile package.
 * (c) Sergio De Simone, Freescapes Labs
 * Parts of this file (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDSRemoteFileManager.h"
#import <objc/message.h>

@interface SDSRemoteFileCombinedOperation : NSObject <SDSRemoteFileOperation>

@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;
@property (copy, nonatomic) void (^cancelBlock)();

@end

@interface SDSRemoteFileManager ()

@property (strong, nonatomic, readwrite) SDSFileCache *imageCache;
@property (strong, nonatomic, readwrite) SDSFileDownloader *imageDownloader;
@property (strong, nonatomic) NSMutableArray *failedURLs;
@property (strong, nonatomic) NSMutableArray *runningOperations;

@end

@implementation SDSRemoteFileManager

+ (id)sharedManager
{
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{instance = self.new;});
    return instance;
}

- (id)init
{
    if ((self = [super init]))
    {
        _imageCache = [self createCache];
        _imageDownloader = SDSFileDownloader.new;
        _failedURLs = NSMutableArray.new;
        _runningOperations = NSMutableArray.new;
    }
    return self;
}

- (SDSFileCache *)createCache
{
    return [SDSFileCache sharedFileCache];
}

- (NSString *)cacheKeyForURL:(NSURL *)url
{
    if (self.cacheKeyFilter)
    {
        return self.cacheKeyFilter(url);
    }
    else
    {
        return [url absoluteString];
    }
}

- (id<SDSRemoteFileOperation>)downloadWithURL:(NSURL *)url options:(SDSRemoteFileOptions)options progress:(SDSFileDownloaderProgressBlock)progressBlock completed:(SDSRemoteFileCompletedWithFinishedBlock)completedBlock
{    
    if ([url isKindOfClass:NSString.class]) {
        url = [NSURL URLWithString:(NSString *)url];
    }

    // Prevents app crashing on argument type error like sending NSNull instead of NSURL
    if (![url isKindOfClass:NSURL.class]) {
        url = nil;
    }

    __block SDSRemoteFileCombinedOperation *operation = SDSRemoteFileCombinedOperation.new;
    __weak SDSRemoteFileCombinedOperation *weakOperation = operation;
    
    BOOL isFailedUrl = NO;
    @synchronized(self.failedURLs)
    {
        isFailedUrl = [self.failedURLs containsObject:url];
    }

    if (!url || !completedBlock || (!(options & SDSRemoteFileRetryFailed) && isFailedUrl))
    {
        if (completedBlock)
        {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil];
            completedBlock(nil, error, SDSFileCacheTypeNone, YES);
        }
        return operation;
    }

    @synchronized(self.runningOperations)
    {
        [self.runningOperations addObject:operation];
    }
    
    NSString *key = [self cacheKeyForURL:url];

    [self.imageCache queryDiskCacheForKey:key done:^(NSData *fileData, SDSFileCacheType cacheType)
    {
        if (operation.isCancelled) return;

        if ((!fileData || options & SDSRemoteFileRefreshCached) && (![self.delegate respondsToSelector:@selector(remoteFileManager:shouldDownloadDataForURL:)] || [self.delegate remoteFileManager:self shouldDownloadDataForURL:url]))
        {
            if (fileData && options & SDSRemoteFileRefreshCached)
            {
                // If fileData was found in the cache bug SDSRemoteFileRefreshCached is provided, notify about the cached fileData
                // AND try to re-download it in order to let a chance to NSURLCache to refresh it from server.
                completedBlock(fileData, nil, cacheType, YES);
            }

            // download if no fileData or requested to refresh anyway, and download allowed by delegate
            SDSFileDownloaderOptions downloaderOptions = 0;
            if (options & SDSRemoteFileLowPriority) downloaderOptions |= SDSFileDownloaderLowPriority;
            if (options & SDSRemoteFileProgressiveDownload) downloaderOptions |= SDSFileDownloaderProgressiveDownload;
            if (options & SDSRemoteFileRefreshCached) downloaderOptions |= SDSFileDownloaderUseNSURLCache;
            if (fileData && options & SDSRemoteFileRefreshCached)
            {
                // force progressive off if fileData already cached but forced refreshing
                downloaderOptions &= ~SDSFileDownloaderProgressiveDownload;
                // ignore fileData read from NSURLCache if fileData if cached but force refreshing
                downloaderOptions |= SDSFileDownloaderIgnoreCachedResponse;
            }
            __block id<SDSRemoteFileOperation> subOperation = [self.imageDownloader downloadFileWithURL:url options:downloaderOptions progress:progressBlock completed:^(NSData *fileData, NSError *error, BOOL finished)
            {                
                if (weakOperation.cancelled)
                {
                    completedBlock(nil, nil, SDSFileCacheTypeNone, finished);
                }
                else if (error)
                {
                    completedBlock(nil, error, SDSFileCacheTypeNone, finished);

                    if (error.code != NSURLErrorNotConnectedToInternet)
                    {
                        @synchronized(self.failedURLs)
                        {
                            [self.failedURLs addObject:url];
                        }
                    }
                }
                else
                {
                    BOOL cacheOnDisk = !(options & SDSRemoteFileCacheMemoryOnly);

                    if (options & SDSRemoteFileRefreshCached && fileData)
                    {
                        // fileData refresh hit the NSURLCache cache, do not call the completion block
                    }
                    else
                    {
                        completedBlock(fileData, nil, SDSFileCacheTypeNone, finished);

                        if (fileData && finished)
                        {
                            [self.imageCache storeData:fileData forKey:key toDisk:cacheOnDisk];
                        }
                    }
                }

                if (finished)
                {
                    @synchronized(self.runningOperations)
                    {
                        [self.runningOperations removeObject:operation];
                    }
                }
            }];
            operation.cancelBlock = ^{[subOperation cancel];};
        }
        else if (fileData)
        {
            completedBlock(fileData, nil, cacheType, YES);
            @synchronized(self.runningOperations)
            {
                [self.runningOperations removeObject:operation];
            }
        }
        else
        {
            // fileData not in cache and download disallowed by delegate
            completedBlock(nil, nil, SDSFileCacheTypeNone, YES);
            @synchronized(self.runningOperations)
            {
                [self.runningOperations removeObject:operation];
            }
        }
    }];

    return operation;
}

- (void)cancelAll
{
    @synchronized(self.runningOperations)
    {
        [self.runningOperations makeObjectsPerformSelector:@selector(cancel)];
        [self.runningOperations removeAllObjects];
    }
}

- (BOOL)isRunning
{
    return self.runningOperations.count > 0;
}

@end

@implementation SDSRemoteFileCombinedOperation

- (void)setCancelBlock:(void (^)())cancelBlock
{
    if (self.isCancelled)
    {
        if (cancelBlock) cancelBlock();
    }
    else
    {
        _cancelBlock = [cancelBlock copy];
    }
}

- (void)cancel
{
    self.cancelled = YES;
    if (self.cancelBlock)
    {
        self.cancelBlock();
        self.cancelBlock = nil;
    }
}

@end
