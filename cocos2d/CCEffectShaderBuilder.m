//
//  CCEffectShaderBuilder.m
//  cocos2d
//
//  Created by Thayer J Andrews on 3/9/15.
//
//

#import "CCEffectShaderBuilder.h"
#import "CCEffectFunction.h"

@implementation CCEffectShaderBuilder

- (id)initWithType:(CCEffectShaderBuilderType)type functions:(NSArray *)functions calls:(NSArray *)calls temporaries:(NSArray *)temporaries
{
    NSAssert(functions, @"");
    NSAssert(calls, @"");
    
    if((self = [super init]))
    {
        // Error check the supplied function objects
        for(CCEffectFunction *function in functions)
        {
            NSAssert([function isKindOfClass:[CCEffectFunction class]], @"Expected a CCEffectFunction and found something else.");
        }

        // Error check the supplied function call objects
        for(CCEffectFunctionCall *call in calls)
        {
            NSAssert([call isKindOfClass:[CCEffectFunctionCall class]], @"Expected a CCEffectFunctionCall and found something else.");
        }
        
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
