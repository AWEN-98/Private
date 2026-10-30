#import "XFChatStore.h"
@implementation XFChatStore
+ (NSString *)path {
    NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/XiaoFeiAgent"];
    [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions:@0700,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:NULL];
    return [root stringByAppendingPathComponent:@"chats.plist"];
}
+ (NSString *)imageFolder {
    NSString *root=[[self path] stringByDeletingLastPathComponent];
    NSString *folder=[root stringByAppendingPathComponent:@"images"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder
       withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    return folder;
}
+ (NSString *)safeImagePath:(NSString *)name {
    if(![name isKindOfClass:[NSString class]] || name.length<10 || name.length>64 ||
       ![name hasSuffix:@".jpg"] || [name rangeOfString:@"/"].location!=NSNotFound ||
       [name rangeOfString:@".."].location!=NSNotFound)return nil;
    return [[self imageFolder] stringByAppendingPathComponent:name];
}
+ (NSString *)saveImage:(UIImage *)image {
    if(!image || image.size.width<1 || image.size.height<1)return nil;
    // Preserve useful gallery quality for generated images while bounding iPhone 4S memory.
    CGFloat factor=MIN(1.0,1280.0/MAX(image.size.width,image.size.height));
    CGSize size=CGSizeMake(MAX(1,round(image.size.width*factor)),
       MAX(1,round(image.size.height*factor)));
    UIGraphicsBeginImageContextWithOptions(size,YES,1.0);
    [image drawInRect:CGRectMake(0,0,size.width,size.height)];
    UIImage *small=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSData *data=UIImageJPEGRepresentation(small,0.78);
    if(!data.length)return nil;
    NSString *name=[[[NSUUID UUID] UUIDString] stringByAppendingString:@".jpg"];
    NSString *path=[self safeImagePath:name];
    if(![data writeToFile:path atomically:YES])return nil;
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:NULL];
    return name;
}
+ (UIImage *)imageForName:(NSString *)filename {
    NSString *path=[self safeImagePath:filename];
    if(!path)return nil;
    return [UIImage imageWithContentsOfFile:path];
}
+ (UIImage *)thumbnailForName:(NSString *)filename {
    UIImage *image=[self imageForName:filename];
    if(!image)return nil;
    CGFloat factor=MIN(1.0,150.0/MAX(image.size.width,image.size.height));
    if(factor>=1)return image;
    CGSize size=CGSizeMake(MAX(1,round(image.size.width*factor)),MAX(1,round(image.size.height*factor)));
    UIGraphicsBeginImageContextWithOptions(size,NO,1.0);
    [image drawInRect:CGRectMake(0,0,size.width,size.height)];
    UIImage *thumb=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return thumb;
}
+ (NSMutableArray *)loadChats {
    NSArray *all=[NSArray arrayWithContentsOfFile:[self path]];
    return all?[all mutableCopy]:[NSMutableArray array];
}
+ (void)persist:(NSArray *)data {
    NSString *path=[self path];
    if([data writeToFile:path atomically:YES]) {
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}
            ofItemAtPath:path error:NULL];
    }
}
+ (NSArray *)conversations {return [self loadChats];}
+ (NSDictionary *)conversationForID:(NSString *)cid {
    for(NSDictionary *item in [self loadChats]) if([item[@"id"] isEqualToString:cid]) return item;
    return nil;
}
+ (NSString *)createConversation {
    NSString *cid=[[NSUUID UUID] UUIDString];
    NSMutableArray *all=[self loadChats];
    [all insertObject:@{@"id":cid,@"title":@"新对话",@"messages":@[],
        @"updated":@([[NSDate date] timeIntervalSince1970])} atIndex:0];
    [self persist:all];
    return cid;
}
+ (void)saveConversationID:(NSString *)cid messages:(NSArray *)messages {
    if(!cid.length) return;
    NSMutableArray *all=[self loadChats];
    NSInteger index=NSNotFound;
    NSDictionary *before=nil;
    for(NSUInteger i=0;i<all.count;i++) if([all[i][@"id"] isEqualToString:cid]) {index=(NSInteger)i;before=all[i];break;}
    if(index==NSNotFound) return;
    NSMutableArray *safe=[NSMutableArray array];
    for (NSDictionary *msg in messages) {
        if(![msg isKindOfClass:[NSDictionary class]]) continue;
        NSString *role=msg[@"role"],*body=msg[@"content"];
        if(![role isKindOfClass:[NSString class]] || ![body isKindOfClass:[NSString class]]) continue;
        if([body length]>24000) body=[body substringToIndex:24000];
        NSString *imageName=msg[@"image_file"];
        if([self safeImagePath:imageName] && [[NSFileManager defaultManager] fileExistsAtPath:[self safeImagePath:imageName]]){
            [safe addObject:@{@"role":role,@"content":body,@"image_file":imageName}];
        }else{
            [safe addObject:@{@"role":role,@"content":body}];
        }
    }
    while(safe.count>60) [safe removeObjectAtIndex:0];
    NSString *title=before[@"title"];
    if([title isEqualToString:@"新对话"] && safe.count) {
        NSString *first=safe[0][@"content"];
        title=[first substringToIndex:MIN((NSUInteger)20,first.length)];
    }
    [all removeObjectAtIndex:index];
    [all insertObject:@{@"id":cid,@"title":title?:@"新对话",@"messages":safe,
        @"updated":@([[NSDate date] timeIntervalSince1970])} atIndex:0];
    while(all.count>80) [all removeLastObject];
    [self persist:all];
}
+ (void)renameConversationID:(NSString *)cid title:(NSString *)title {
    if(!title.length) return;
    NSMutableArray *all=[self loadChats];
    for(NSInteger i=0;i<(NSInteger)all.count;i++) if([all[i][@"id"] isEqualToString:cid]) {
        NSMutableDictionary *d=[all[i] mutableCopy];d[@"title"]=title;
        all[i]=d;break;
    }
    [self persist:all];
}
+ (void)deleteConversationID:(NSString *)cid {
    NSMutableArray *all=[self loadChats];
    NSIndexSet *set=[all indexesOfObjectsPassingTest:^BOOL(NSDictionary *d,NSUInteger i,BOOL *stop){
        return [d[@"id"] isEqualToString:cid];
    }];
    [all removeObjectsAtIndexes:set];
    [self persist:all];
}
@end
