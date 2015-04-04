//
//  CCEffectShaderBuilder.m
//  cocos2d
//
//  Created by Thayer J Andrews on 3/9/15.
//
//

#import "CCEffectShaderBuilder.h"


@implementation CCEffectShaderBuilder

- (id)initWithType:(CCEffectShaderBuilderType)type functions:(NSArray *)functions calls:(NSArray *)calls temporaries:(NSArray *)temporaries
{
    NSAssert(functions, @"");
    NSAssert(calls, @"");
    
    if((self = [super init]))
    {
        _type = type;
        _functions = [functions copy];
        _calls = [calls copy];
        _temporaries = [temporaries copy];
    }
    return self;
}

- (NSArray *)parameters
{
    NSAssert(0, @"Subclasses must override this.");
    return nil;
}

@end
