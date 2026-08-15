#import "ThumbnailProvider.h"
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static void LogToFile(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSString *logLine = [NSString stringWithFormat:@"%@: %@\n", [NSDate date], message];
    NSData *data = [logLine dataUsingEncoding:NSUTF8StringEncoding];
    
    NSFileHandle *fileHandler = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/qljava.log"];
    if (!fileHandler) {
        [[NSFileManager defaultManager] createFileAtPath:@"/tmp/qljava.log" contents:nil attributes:nil];
        fileHandler = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/qljava.log"];
    }
    
    @try {
        [fileHandler seekToEndOfFile];
        [fileHandler writeData:data];
        [fileHandler closeFile];
    } @catch (NSException *e) {
        NSLog(@"Failed to write to log file: %@", e);
    }
}

@implementation ThumbnailProvider

+ (void)load {
    LogToFile(@"ThumbnailProvider class loaded in runtime!");
}

- (instancetype)init {
    self = [super init];
    if (self) {
        LogToFile(@"ThumbnailProvider instance initialized!");
    }
    return self;
}

- (void)provideThumbnailForFileRequest:(QLFileThumbnailRequest *)request
                     completionHandler:(void (^)(QLThumbnailReply * _Nullable reply, NSError * _Nullable error))completionHandler
{
    @autoreleasepool {
        LogToFile(@"--- QLJava Thumbnail Request Started ---");
        
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        NSString *shPath = [bundle pathForResource:@"qlt" ofType:@"sh"];
        
        if (!shPath) {
            LogToFile(@"Error: qlt.sh not found in bundle: %@", bundle.resourcePath);
            NSError *error = [NSError errorWithDomain:@"com.vavi.QLJava.Thumbnail"
                                                 code:1
                                             userInfo:@{NSLocalizedDescriptionKey: @"qlt.sh script not found in resources bundle."}];
            completionHandler(nil, error);
            return;
        }
        
        NSURL *fileName = request.fileURL;
        LogToFile(@"Thumbnail Target file: %@", fileName.path);
        LogToFile(@"Thumbnail Script path: %@", shPath);
        LogToFile(@"Thumbnail Bundle resource path: %@", bundle.resourcePath);
        
        NSPipe *pipe = [NSPipe pipe];
        NSPipe *errPipe = [NSPipe pipe];
        
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
        task.arguments = @[shPath, fileName.path, bundle.resourcePath];
        task.standardOutput = pipe;
        task.standardError = errPipe;
        
        NSError *launchError = nil;
        if (![task launchAndReturnError:&launchError]) {
            LogToFile(@"Thumbnail failed to launch task: %@", launchError);
            completionHandler(nil, launchError);
            return;
        }
        
        __block NSData *data = nil;
        __block NSData *errData = nil;
        dispatch_group_t group = dispatch_group_create();
        
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            data = [pipe.fileHandleForReading readDataToEndOfFileAndReturnError:nil];
            dispatch_group_leave(group);
        });
        
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            errData = [errPipe.fileHandleForReading readDataToEndOfFileAndReturnError:nil];
            dispatch_group_leave(group);
        });
        
        [task waitUntilExit];
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        
        if (errData.length > 0) {
            NSString *errStr = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
            LogToFile(@"Thumbnail Task stderr:\n%@", errStr);
        }
        
        LogToFile(@"Thumbnail Task exited with status: %d, output bytes: %lu", task.terminationStatus, (unsigned long)data.length);
        
        [pipe.fileHandleForReading closeFile];
        [errPipe.fileHandleForReading closeFile];
        
        if (data.length > 0) {
            NSString *outStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSRange b64Start = [outStr rangeOfString:@"data:image/png;base64,"];
            if (b64Start.location != NSNotFound) {
                NSUInteger startIdx = b64Start.location + b64Start.length;
                NSRange quoteRange = [outStr rangeOfString:@"\"" options:0 range:NSMakeRange(startIdx, outStr.length - startIdx)];
                if (quoteRange.location != NSNotFound) {
                    NSString *base64String = [outStr substringWithRange:NSMakeRange(startIdx, quoteRange.location - startIdx)];
                    base64String = [base64String stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    NSData *pngData = [[NSData alloc] initWithBase64EncodedString:base64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
                    if (pngData && pngData.length > 0) {
                        NSImage *image = [[NSImage alloc] initWithData:pngData];
                        if (image) {
                            CGSize imageSize = image.size;
                            if (imageSize.width <= 0 || imageSize.height <= 0) {
                                imageSize = request.maximumSize;
                            }
                            LogToFile(@"Thumbnail generated image size: %.0fx%.0f", imageSize.width, imageSize.height);
                            QLThumbnailReply *reply = [QLThumbnailReply replyWithContextSize:imageSize currentContextDrawingBlock:^BOOL{
                                [image drawInRect:NSMakeRect(0, 0, imageSize.width, imageSize.height)];
                                return YES;
                            }];
                            completionHandler(reply, nil);
                            LogToFile(@"--- QLJava Thumbnail Request Finished Successfully ---");
                            return;
                        }
                    }
                }
            }
        }
        
        NSError *error = [NSError errorWithDomain:@"com.vavi.QLJava.Thumbnail"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Could not parse image thumbnail output."}];
        completionHandler(nil, error);
        LogToFile(@"--- QLJava Thumbnail Request Finished With Error ---");
    }
}

@end
