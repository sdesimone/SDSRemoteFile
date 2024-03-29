/*
 * This file is part of the SDSRemoteFile package.
 * (c) Sergio De Simone, Freescapes Labs
 * Parts of this file (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDSFileCache.h"
#import "SDSRemoteFileOperation.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach.h>
#import <mach/mach_host.h>

static const NSInteger kDefaultCacheMaxCacheAge = 60 * 60 * 24 * 30; // 1 month

@interface SDSFileCache ()

@property (strong, nonatomic) NSCache *memCache;
@property (strong, nonatomic) NSString *diskCachePath;
@property (SDDispatchQueueSetterSementics, nonatomic) dispatch_queue_t ioQueue;

@end


@implementation SDSFileCache

+ (SDSFileCache *)sharedFileCache
{
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{instance = self.new;});
    return instance;
}

- (id)init
{
    return [self initWithNamespace:@"default"];
}

- (id)initWithNamespace:(NSString *)ns
{
    if ((self = [super init]))
    {
        NSString *fullNamespace = [@"com.hackemist.SDSRemoteFileCache." stringByAppendingString:ns];

        // Create IO serial queue
        _ioQueue = dispatch_queue_create("com.hackemist.SDSRemoteFileCache", DISPATCH_QUEUE_SERIAL);

        // Init default values
        _maxCacheAge = kDefaultCacheMaxCacheAge;

        // Init the memory cache
        _memCache = [[NSCache alloc] init];
        _memCache.name = fullNamespace;

        // Init the disk cache
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        _diskCachePath = [paths[0] stringByAppendingPathComponent:fullNamespace];

#if TARGET_OS_IPHONE
        // Subscribe to app events
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clearMemory)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cleanDisk)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
#endif
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    SDDispatchQueueRelease(_ioQueue);
}

#pragma mark SDSFileCache (private)

- (NSString *)cachePathForKey:(NSString *)key
{
    const char *str = [key UTF8String];
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14], r[15]];

    return [self.diskCachePath stringByAppendingPathComponent:filename];
}

#pragma mark ImageCache

- (void)storeData:(NSData*)imageData forKey:(NSString *)key toDisk:(BOOL)toDisk
{
    if (!imageData || !key)
    {
        return;
    }

    [self.memCache setObject:imageData forKey:key cost:imageData.length];

    if (toDisk)
    {
        dispatch_async(self.ioQueue, ^
        {
            // Can't use defaultManager another thread
            NSFileManager *fileManager = NSFileManager.new;

            if (![fileManager fileExistsAtPath:_diskCachePath])
            {
                [fileManager createDirectoryAtPath:_diskCachePath withIntermediateDirectories:YES attributes:nil error:NULL];
            }

            [fileManager createFileAtPath:[self cachePathForKey:key] contents:imageData attributes:nil];
        });
    }
}

- (void)storeData:(NSData*)fileData forKey:(NSString *)key
{
    [self storeData:fileData forKey:key toDisk:YES];
}

- (NSData *)fileDataFromMemoryCacheForKey:(NSString *)key
{
    return [self.memCache objectForKey:key];
}

- (NSData *)fileDataFromDiskCacheForKey:(NSString *)key
{
    // First check the in-memory cache...
    NSData *fileData = [self fileDataFromMemoryCacheForKey:key];
    if (fileData)
    {
        return fileData;
    }
    
    // Second check the disk cache...
    fileData = [self fileDataForKey:key];
    if (fileData)
    {
//        CGFloat cost = fileData.size.height * fileData.size.width * fileData.scale;
        [self.memCache setObject:fileData forKey:key cost:fileData.length];
    }
    
    return fileData;
}

- (NSData*)fileDataForKey:(NSString *)key
{
    NSString *path = [self cachePathForKey:key];
    return [NSData dataWithContentsOfFile:path];
}

- (void)queryDiskCacheForKey:(NSString *)key done:(void (^)(NSData *fileData, SDSFileCacheType cacheType))doneBlock
{
    if (!doneBlock) return;

    if (!key)
    {
        doneBlock(nil, SDSFileCacheTypeNone);
        return;
    }

    // First check the in-memory cache...
    NSData *fileData = [self fileDataFromMemoryCacheForKey:key];
    if (fileData)
    {
        doneBlock(fileData, SDSFileCacheTypeMemory);
        return;
    }

    dispatch_async(self.ioQueue, ^
    {
        @autoreleasepool
        {
            NSData *fileData = [self fileDataForKey:key];
            if (fileData)
            {
                [self.memCache setObject:fileData forKey:key cost:fileData.length];
            }

            dispatch_async(dispatch_get_main_queue(), ^
            {
                doneBlock(fileData, SDSFileCacheTypeDisk);
            });
        }
    });
}

- (void)removeFileDataForKey:(NSString *)key
{
    [self removeFileDataForKey:key fromDisk:YES];
}

- (void)removeFileDataForKey:(NSString *)key fromDisk:(BOOL)fromDisk
{
    if (key == nil)
    {
        return;
    }

    [self.memCache removeObjectForKey:key];

    if (fromDisk)
    {
        dispatch_async(self.ioQueue, ^
        {
            [[NSFileManager defaultManager] removeItemAtPath:[self cachePathForKey:key] error:nil];
        });
    }
}

- (void)clearMemory
{
    [self.memCache removeAllObjects];
}

- (void)clearDisk
{
    dispatch_async(self.ioQueue, ^
    {
        [[NSFileManager defaultManager] removeItemAtPath:self.diskCachePath error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:self.diskCachePath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
    });
}

- (void)cleanDisk
{
    dispatch_async(self.ioQueue, ^
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *diskCacheURL = [NSURL fileURLWithPath:self.diskCachePath isDirectory:YES];
        NSArray *resourceKeys = @[ NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey ];

        // This enumerator prefetches useful properties for our cache files.
        NSDirectoryEnumerator *fileEnumerator = [fileManager enumeratorAtURL:diskCacheURL
                                                  includingPropertiesForKeys:resourceKeys
                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                errorHandler:NULL];

        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-self.maxCacheAge];
        NSMutableDictionary *cacheFiles = [NSMutableDictionary dictionary];
        unsigned long long currentCacheSize = 0;

        // Enumerate all of the files in the cache directory.  This loop has two purposes:
        //
        //  1. Removing files that are older than the expiration date.
        //  2. Storing file attributes for the size-based cleanup pass.
        for (NSURL *fileURL in fileEnumerator)
        {
            NSDictionary *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:NULL];

            // Skip directories.
            if ([resourceValues[NSURLIsDirectoryKey] boolValue])
            {
                continue;
            }

            // Remove files that are older than the expiration date;
            NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
            if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate])
            {
                [fileManager removeItemAtURL:fileURL error:nil];
                continue;
            }

            // Store a reference to this file and account for its total size.
            NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
            currentCacheSize += [totalAllocatedSize unsignedLongLongValue];
            [cacheFiles setObject:resourceValues forKey:fileURL];
        }

        // If our remaining disk cache exceeds a configured maximum size, perform a second
        // size-based cleanup pass.  We delete the oldest files first.
        if (self.maxCacheSize > 0 && currentCacheSize > self.maxCacheSize)
        {
            // Target half of our maximum cache size for this cleanup pass.
            const unsigned long long desiredCacheSize = self.maxCacheSize / 2;

            // Sort the remaining cache files by their last modification time (oldest first).
            NSArray *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                            usingComparator:^NSComparisonResult(id obj1, id obj2)
            {
                return [obj1[NSURLContentModificationDateKey] compare:obj2[NSURLContentModificationDateKey]];
            }];

            // Delete files until we fall below our desired cache size.
            for (NSURL *fileURL in sortedFiles)
            {
                if ([fileManager removeItemAtURL:fileURL error:nil])
                {
                    NSDictionary *resourceValues = cacheFiles[fileURL];
                    NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                    currentCacheSize -= [totalAllocatedSize unsignedLongLongValue];

                    if (currentCacheSize < desiredCacheSize)
                    {
                        break;
                    }
                }
            }
        }
    });
}

-(unsigned long long)getSize
{
    unsigned long long size = 0;
    NSDirectoryEnumerator *fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:self.diskCachePath];
    for (NSString *fileName in fileEnumerator)
    {
        NSString *filePath = [self.diskCachePath stringByAppendingPathComponent:fileName];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        size += [attrs fileSize];
    }
    return size;
}

- (int)getDiskCount
{
    int count = 0;
    NSDirectoryEnumerator *fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:self.diskCachePath];
    for (NSString *fileName in fileEnumerator)
    {
        count += 1;
    }
    
    return count;
}

@end
