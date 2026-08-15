#import "PreviewProvider.h"
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

@implementation PreviewProvider

+ (void)load {
    LogToFile(@"PreviewProvider class loaded in runtime!");
}

- (instancetype)init {
    self = [super init];
    if (self) {
        LogToFile(@"PreviewProvider instance initialized!");
    }
    return self;
}

- (void)providePreviewForFileRequest:(QLFilePreviewRequest *)request
                   completionHandler:(void (^)(QLPreviewReply * _Nullable reply, NSError * _Nullable error))completionHandler
{
    @autoreleasepool {
        LogToFile(@"--- QLJava Request Started ---");
        
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        NSString *shPath = [bundle pathForResource:@"ql" ofType:@"sh"];
        
        if (!shPath) {
            LogToFile(@"Error: ql.sh not found in bundle: %@", bundle.resourcePath);
            NSError *error = [NSError errorWithDomain:@"com.vavi.QLJava"
                                                 code:1
                                             userInfo:@{NSLocalizedDescriptionKey: @"ql.sh script not found in resources bundle."}];
            completionHandler(nil, error);
            return;
        }
        
        NSURL *fileName = request.fileURL;
        LogToFile(@"Target file: %@", fileName.path);
        LogToFile(@"Script path: %@", shPath);
        LogToFile(@"Bundle resource path: %@", bundle.resourcePath);
        
        NSPipe *pipe = [NSPipe pipe];
        NSPipe *errPipe = [NSPipe pipe];
        
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
        task.arguments = @[shPath, fileName.path, bundle.resourcePath];
        task.standardOutput = pipe;
        task.standardError = errPipe;
        
        NSError *launchError = nil;
        if (![task launchAndReturnError:&launchError]) {
            LogToFile(@"Failed to launch task: %@", launchError);
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
            LogToFile(@"Task stderr:\n%@", errStr);
        }
        
        if (data.length > 0) {
            NSString *outStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            LogToFile(@"Task stdout:\n%@", outStr);
        }
        
        QLPreviewReply *reply = nil;
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
                        CGSize imageSize = image ? image.size : CGSizeMake(800, 600);
                        LogToFile(@"Preview identified as native PNG image (size: %.0fx%.0f)", imageSize.width, imageSize.height);
                        reply = [[QLPreviewReply alloc] initWithDataOfContentType:UTTypePNG
                                                                     contentSize:imageSize
                                                              dataCreationBlock:^NSData * _Nullable(QLPreviewReply * _Nonnull reply, NSError * _Nullable __autoreleasing * _Nullable error) {
                            return pngData;
                        }];
                    }
                }
            }
        }
        
        if (!reply) {
            reply = [[QLPreviewReply alloc] initWithDataOfContentType:UTTypeHTML
                                                         contentSize:CGSizeMake(800, 600)
                                                  dataCreationBlock:^NSData * _Nullable(QLPreviewReply * _Nonnull reply, NSError * _Nullable __autoreleasing * _Nullable error) {
                return data;
            }];
        }
        
        completionHandler(reply, nil);
        LogToFile(@"--- QLJava Request Finished ---");
    }
}

@end
