//
//  CCEffectShader.m
//  cocos2d
//
//  Created by Thayer J Andrews on 3/9/15.
//
//

#import "CCEffectShader.h"
#import "CCEffectParameterProtocol.h"
#import "CCEffectShaderBuilder.h"
#import "CCShader.h"


@interface CCEffectShader ()
@property (nonatomic, assign) BOOL compileAttempted;
@end


@implementation CCEffectShader

@synthesize shader = _shader;
@synthesize parameters = _parameters;

- (id)initWithVertexShaderBuilder:(CCEffectShaderBuilder *)vtxBuilder fragmentShaderBuilder:(CCEffectShaderBuilder *)fragBuilder
{
    NSAssert(vtxBuilder, @"");
    NSAssert(fragBuilder, @"");
    
    if((self = [super init]))
    {
        _vertexShaderBuilder = vtxBuilder;
        _fragmentShaderBuilder = fragBuilder;
        _shader = nil;
        _parameters = nil;
        
        _compileAttempted = NO;
        
    }
    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    // CCEffectShader is immutable so no need to really copy.
    return self;
}

- (CCShader *)shader
{
    // Only compile the shader on-demand and only do so once. If compilation
    // fails, we just return nil and that's okay.
    if (!self.compileAttempted)
    {
        _shader = [[CCShader alloc] initWithVertexShaderSource:_vertexShaderBuilder.shaderSource fragmentShaderSource:_fragmentShaderBuilder.shaderSource];
        self.compileAttempted = YES;
    }
    return _shader;
}

- (NSDictionary *)parameters
{
    if (!_parameters)
    {
        NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
        for(id<CCEffectParameterProtocol> parameter in _vertexShaderBuilder.parameters)
        {
            parameters[parameter.name] = parameter.value;
        }
        for(id<CCEffectParameterProtocol> parameter in _fragmentShaderBuilder.parameters)
        {
            parameters[parameter.name] = parameter.value;
        }
        _parameters = [parameters copy];
    }
    return _parameters;
}

@end
