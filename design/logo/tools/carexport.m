#import <AppKit/AppKit.h>
#import <objc/message.h>

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: carexport Assets.car outdir\n"); return 2; }
    @autoreleasepool {
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreUI.framework"] load];
        Class cls = NSClassFromString(@"CUICatalog");
        NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
        NSString *out = @(argv[2]);
        [[NSFileManager defaultManager] createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *err = nil;
        id (*initCatalog)(id, SEL, id, NSError **) = (id (*)(id, SEL, id, NSError **))objc_msgSend;
        id catalog = initCatalog([cls alloc], @selector(initWithURL:error:), url, &err);
        if (!catalog) { fprintf(stderr, "no catalog %s\n", err.description.UTF8String); return 1; }
        NSArray *names = [catalog performSelector:@selector(allImageNames)];
        int count = 0;
        for (NSString *name in names) {
            if (![name hasPrefix:@"AppIcon"] || [name containsString:@"/"]) continue;
            NSArray *images = [catalog performSelector:@selector(imagesWithName:) withObject:name];
            for (id img in images) {
                if (![img respondsToSelector:@selector(image)]) continue;
                CGImageRef cg = (__bridge CGImageRef)[img performSelector:@selector(image)];
                if (!cg) continue;
                NSString *appearance = [[img valueForKey:@"appearance"] description] ?: @"default";
                long idiom = [[img valueForKey:@"idiom"] longValue];
                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
                NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSString *file = [out stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%zupx-%@-idiom%ld.png", name, CGImageGetWidth(cg), appearance, idiom]];
                [png writeToFile:file atomically:YES];
                printf("wrote %s alpha=%d\n", file.lastPathComponent.UTF8String, (int)CGImageGetAlphaInfo(cg));
                count++;
            }
        }
        printf("exported %d\n", count);
    }
    return 0;
}
