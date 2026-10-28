#import "XFChatStore.h"
@implementation XFChatStore
+ (NSString *)path {
    NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/XiaoFeiAgent"];
    [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions:@0700,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:NULL];
    return [root stringByAppendingPathComponent:@"chats.plist"];
}
+ (NSMutableArray *)load {
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
+ (NSArray *)conversations {return [self load];}
+ (NSDictionary *)conversationForID:(NSString *)cid {
    for(NSDictionary *item in [self load]) if([item[@"id"] isEqualToString:cid]) return item;
    return nil;
}
+ (NSString *)createConversation {
    NSString *cid=[[NSUUID UUID] UUIDString];
    NSMutableArray *all=[self load];
    [all insertObject:@{@"id":cid,@"title":@"新对话",@"messages":@[],
        @"updated":@([[NSDate date] timeIntervalSince1970])} atIndex:0];
    [self persist:all];
    return cid;
}
+ (void)saveConversationID:(NSString *)cid messages:(NSArray *)messages {
    if(!cid.length) return;
    NSMutableArray *all=[self load];
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
        [safe addObject:@{@"role":role,@"content":body}];
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
    NSMutableArray *all=[self load];
    for(NSInteger i=0;i<(NSInteger)all.count;i++) if([all[i][@"id"] isEqualToString:cid]) {
        NSMutableDictionary *d=[all[i] mutableCopy];d[@"title"]=title;
        all[i]=d;break;
    }
    [self persist:all];
}
+ (void)deleteConversationID:(NSString *)cid {
    NSMutableArray *all=[self load];
    NSIndexSet *set=[all indexesOfObjectsPassingTest:^BOOL(NSDictionary *d,NSUInteger i,BOOL *stop){
        return [d[@"id"] isEqualToString:cid];
    }];
    [all removeObjectsAtIndexes:set];
    [self persist:all];
}
@end
