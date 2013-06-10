/*
 * This file is part of the SDSRemoteFile package.
 * (c) Sergio De Simone, Freescapes Labs
 * Parts of this file (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDSFileDownloaderOperation.h"

@interface SDSFileDownloaderOperation ()

@property (copy, nonatomic) SDSFileDownloaderProgressBlock progressBlock;
@property (copy, nonatomic) SDSFileDownloaderCompletedBlock completedBlock;
@property (copy, nonatomic) void (^cancelBlock)();

@property (assign, nonatomic, getter = isExecuting) BOOL executing;
@property (assign, nonatomic, getter = isFinished) BOOL finished;
@property (assign, nonatomic) long long expectedSize;
@property (strong, nonatomic) NSMutableData *fileData;
@property (strong, nonatomic) NSURLConnection *connection;

@end

@implementation SDSFileDownloaderOperation
{
    size_t width, height;
    BOOL responseFromCached;
}

- (id)initWithRequest:(NSURLRequest *)request options:(SDSFileDownloaderOptions)options progress:(void (^)(NSUInteger, long long))progressBlock completed:(void (^)(NSData *, NSError *, BOOL))completedBlock cancelled:(void (^)())cancelBlock
{
    if ((self = [super init]))
    {
        _request = request;
        _options = options;
        _progressBlock = [progressBlock copy];
        _completedBlock = [completedBlock copy];
        _cancelBlock = [cancelBlock copy];
        _executing = NO;
        _finished = NO;
        _expectedSize = 0;
        responseFromCached = YES; // Initially wrong until `connection:willCacheResponse:` is called or not called
    }
    return self;
}

- (void)start
{
    if (self.isCancelled)
    {
        self.finished = YES;
        [self reset];
        return;
    }

    self.executing = YES;
    self.connection = [NSURLConnection.alloc initWithRequest:self.request delegate:self startImmediately:NO];

    [self.connection start];

    if (self.connection)
    {
        if (self.progressBlock)
        {
            self.progressBlock(0, -1);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:SDSRemoteFileDownloadStartNotification object:self];

        // Make sure to run the runloop in our background thread so it can process downloaded data
        CFRunLoopRun();
    }
    else
    {
        if (self.completedBlock)
        {
            self.completedBlock(nil, [NSError errorWithDomain:NSURLErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Connection can't be initialized"}], YES);
        }
    }
}

- (void)cancel
{
    if (self.isFinished) return;
    [super cancel];
    if (self.cancelBlock) self.cancelBlock();

    if (self.connection)
    {
        [self.connection cancel];
        [[NSNotificationCenter defaultCenter] postNotificationName:SDSRemoteFileDownloadStopNotification object:self];

        // As we cancelled the connection, its callback won't be called and thus won't
        // maintain the isFinished and isExecuting flags.
        if (self.isExecuting) self.executing = NO;
        if (!self.isFinished) self.finished = YES;
    }

    [self reset];
}

- (void)done
{
    self.finished = YES;
    self.executing = NO;
    [self reset];
}

- (void)reset
{
    self.cancelBlock = nil;
    self.completedBlock = nil;
    self.progressBlock = nil;
    self.connection = nil;
    self.fileData = nil;
}

- (void)setFinished:(BOOL)finished
{
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)executing
{
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isConcurrent
{
    return YES;
}

#pragma mark NSURLConnection (delegate)

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if (![response respondsToSelector:@selector(statusCode)] || [((NSHTTPURLResponse *)response) statusCode] < 400)
    {
        NSUInteger expected = response.expectedContentLength > 0 ? (NSUInteger)response.expectedContentLength : 0;
        self.expectedSize = expected;
        if (self.progressBlock)
        {
            self.progressBlock(0, expected);
        }

        self.fileData = [NSMutableData.alloc initWithCapacity:expected];
    }
    else
    {
        [self.connection cancel];

        [[NSNotificationCenter defaultCenter] postNotificationName:SDSRemoteFileDownloadStopNotification object:nil];

        if (self.completedBlock)
        {
            self.completedBlock(nil, [NSError errorWithDomain:NSURLErrorDomain code:[((NSHTTPURLResponse *)response) statusCode] userInfo:nil], YES);
        }

        [self done];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self.fileData appendData:data];

    if (self.progressBlock)
    {
        self.progressBlock(self.fileData.length, self.expectedSize);
    }
}

- (UIImage *)scaledImageForKey:(NSString *)key image:(UIImage *)image
{
    return image;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConnection
{
    CFRunLoopStop(CFRunLoopGetCurrent());
    self.connection = nil;

    [[NSNotificationCenter defaultCenter] postNotificationName:SDSRemoteFileDownloadStopNotification object:nil];

    SDSFileDownloaderCompletedBlock completionBlock = self.completedBlock;

    if (completionBlock)
    {
        if (self.options & SDSFileDownloaderIgnoreCachedResponse && responseFromCached)
        {
            completionBlock(nil, nil, YES);
            self.completionBlock = nil;
            [self done];
        }
        else
        {
            completionBlock(self.fileData, nil, YES);
            self.completionBlock = nil;
            [self done];
        }
    }
    else
    {
        [self done];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    CFRunLoopStop(CFRunLoopGetCurrent());
    [[NSNotificationCenter defaultCenter] postNotificationName:SDSRemoteFileDownloadStopNotification object:nil];

    if (self.completedBlock)
    {
        self.completedBlock(nil, error, YES);
    }

    [self done];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    responseFromCached = NO; // If this method is called, it means the response wasn't read from cache
    if (self.request.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData)
    {
        // Prevents caching of responses
        return nil;
    }
    else
    {
        return cachedResponse;
    }
}


@end
