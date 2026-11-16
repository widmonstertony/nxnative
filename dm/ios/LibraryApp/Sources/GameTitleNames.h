#import <Foundation/Foundation.h>
#include <zlib.h>

static BOOL TonTonTitleHasChinese(NSString *name) {
    for(NSUInteger i=0;i<name.length;i++){
        unichar c=[name characterAtIndex:i];if(c>=0x3400&&c<=0x9fff)return YES;
    }
    return NO;
}
static NSString *TonTonChineseControlTitle(NSString *path) {
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if(![attributes[NSFileType] isEqual:NSFileTypeRegular]||[attributes[NSFileSize] unsignedLongLongValue]>131072)return nil;
    NSData *data=[NSData dataWithContentsOfFile:path];if(!data.length)return nil;
    const unsigned char *bytes=data.bytes;NSData *area=data;
    if(data.length>=2){
        unsigned int size=bytes[0]|((unsigned int)bytes[1]<<8);
        if(size&&size<=data.length-2){
            unsigned char output[0x6001];z_stream stream={0};
            stream.next_in=(Bytef *)bytes+2;stream.avail_in=size;stream.next_out=output;stream.avail_out=sizeof output;
            if(inflateInit2(&stream,-MAX_WBITS)==Z_OK){
                int status=inflate(&stream,Z_FINISH);
                if(status==Z_STREAM_END&&stream.total_out==0x6000)area=[NSData dataWithBytes:output length:0x6000];
                inflateEnd(&stream);
            }
        }
    }
    bytes=area.bytes;
    for(NSNumber *slot in @[@14,@13]){
        NSUInteger offset=slot.unsignedIntegerValue*0x300;
        if(area.length<offset+0x200)continue;
        NSUInteger count=0;while(count<0x200&&bytes[offset+count])count++;
        NSString *name=[[NSString alloc]initWithBytes:bytes+offset length:count encoding:NSUTF8StringEncoding];
        if(name.length&&TonTonTitleHasChinese(name)&&[name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound)return name;
    }
    return nil;
}
static NSString *TonTonPreferredGameTitle(NSString *title,NSString *slot,NSString *bundled) {
    for(NSString *root in @[slot,[bundled stringByAppendingPathComponent:title]]){
        for(NSString *relative in @[@"Resources/control.nacp",@"Resources/dm/control.nacp",@"control.nacp"]){
            NSString *name=TonTonChineseControlTitle([root stringByAppendingPathComponent:relative]);
            if(name.length)return name;
        }
    }
    static NSDictionary *names;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSData *data=[NSData dataWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"GameTitleNames.zh-Hans.json"]];
        id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        names=[value isKindOfClass:NSDictionary.class]?value:@{};
    });
    id entry=names[title.lowercaseString];id name=[entry isKindOfClass:NSDictionary.class]?entry[@"name"]:nil;
    return [name isKindOfClass:NSString.class]&&[name length]?name:nil;
}
