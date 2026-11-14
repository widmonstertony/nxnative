#pragma once
#import <Foundation/Foundation.h>

static NSArray<NSString *> *TTControlButtons(void) {
    return @[@"A",@"B",@"X",@"Y",@"LS",@"RS",@"L",@"R",@"ZL",@"ZR",@"Plus",@"Minus",@"Left",@"Up",@"Right",@"Down"];
}
static NSString *TTControlKey(NSString *title) {
    return title.length ? [NSString stringWithFormat:@"tonton.game.%@.controllerMap",title.lowercaseString] : @"tonton.global.controllerMap";
}
static NSDictionary *TTControlValidated(id value) {
    NSMutableDictionary *out=[NSMutableDictionary new];
    if(![value isKindOfClass:NSDictionary.class])return out;
    NSArray *buttons=TTControlButtons();
    for(id key in value)if([buttons containsObject:key] && ([buttons containsObject:value[key]] || [value[key] isEqual:@"none"]))out[key]=value[key];
    return out;
}
static NSDictionary *TTControlMerged(NSUserDefaults *defaults,NSString *title) {
    NSMutableDictionary *out=[TTControlValidated([defaults objectForKey:TTControlKey(nil)]) mutableCopy];
    if(title.length)[out addEntriesFromDictionary:TTControlValidated([defaults objectForKey:TTControlKey(title)])];
    return out;
}
static NSString *TTControlEnvironment(NSDictionary *mapping) {
    NSMutableArray *pairs=[NSMutableArray new];
    for(NSString *button in TTControlButtons()) {
        NSString *output=mapping[button];
        if(output && ![output isEqual:button])[pairs addObject:[NSString stringWithFormat:@"%@=%@",button,output]];
    }
    return [pairs componentsJoinedByString:@","];
}
static NSString *TTControlLabel(NSString *button) {
    NSDictionary *labels=@{@"LS":@"\u5DE6\u6447\u6746\u6309\u4E0B",@"RS":@"\u53F3\u6447\u6746\u6309\u4E0B",@"Plus":@"\uFF0B",@"Minus":@"\uFF0D",@"Left":@"\u65B9\u5411\u952E\u5DE6",@"Up":@"\u65B9\u5411\u952E\u4E0A",@"Right":@"\u65B9\u5411\u952E\u53F3",@"Down":@"\u65B9\u5411\u952E\u4E0B",@"none":@"\u505C\u7528"};
    return labels[button]?:button;
}
