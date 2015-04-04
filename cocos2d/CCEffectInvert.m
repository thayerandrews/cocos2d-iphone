//
//  CCEffectInvert.m
//  cocos2d-ios
//
//  Created by Nicky Weber on 10/27/14.
//
//

#import "CCEffectInvert.h"
#import "CCDeviceInfo.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"
#import "CCEffect_Private.h"
#import "CCProtocols.h"
#import "CCRendererBasicTypes.h"
#import "CCTexture.h"


#pragma mark - CCEffectInvertImplGL

@interface CCEffectInvertImplGL : CCEffectImpl

@end

@implementation CCEffectInvertImplGL

-(id)init
{
    NSArray *renderPasses = [CCEffectInvertImplGL buildRenderPasses];
    NSArray *shaders = [CCEffectInvertImplGL buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.debugName = @"CCEffectInvertImplGL";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectInvertImplGL fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectInvertImplGL buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"inverted" inputs:@{@"inputValue" : @"tmp"}]];
    
    NSArray *uniforms = @[
                          [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          ];
    
    return [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                               functions:functions
                                                   calls:calls
                                             temporaries:temporaries
                                                uniforms:uniforms
                                                varyings:@[]];
}

+ (NSArray *)buildFragmentFunctions
{
    NSString* effectBody = CC_GLSL(
            return vec4((vec3(inputValue.a) - inputValue.rgb), inputValue.a);
    );
    
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"invertEffect"
                                                                           body:effectBody
                                                                         inputs:@[input]
                                                                     returnType:@"vec4"];

    return @[fragmentFunction];
}

+ (NSArray *)buildRenderPasses
{
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectInvert pass 0";
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){

        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectInvertImplMetal

@interface CCEffectInvertImplMetal : CCEffectImpl

@end

@implementation CCEffectInvertImplMetal

-(id)init
{
    NSArray *renderPasses = [CCEffectInvertImplMetal buildRenderPasses];
    NSArray *shaders = [CCEffectInvertImplMetal buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.debugName = @"CCEffectInvertImplMetal";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderMetal defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectInvertImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectInvertImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"inverted" inputs:@{@"inputValue" : @"tmp"}]];

    CCEffectShaderBuilderMetal *builder = [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                                                 functions:functions
                                                                                     calls:calls
                                                                               temporaries:temporaries
                                                                                 arguments:[CCEffectShaderBuilderMetal defaultFragmentArguments]
                                                                                   structs:[CCEffectShaderBuilderMetal defaultStructDeclarations]];
    return builder;
}

+ (NSArray *)buildFragmentFunctions
{
    NSString* effectBody = CC_GLSL(
                                   return half4((half3(inputValue.a) - inputValue.rgb), inputValue.a);
                                   );
    
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"];
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"invertEffect"
                                                                           body:effectBody
                                                                         inputs:@[input]
                                                                     returnType:@"half4"];
    
    return @[fragmentFunction];
}

+ (NSArray *)buildRenderPasses
{
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectInvert pass 0";
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectInvert

@implementation CCEffectInvert

-(id)init
{
    if((self = [super init]))
    {
        if([CCDeviceInfo sharedDeviceInfo].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectInvertImplMetal alloc] init];
        }
        else
        {
            self.effectImpl = [[CCEffectInvertImplGL alloc] init];
        }
        self.debugName = @"CCEffectInvert";
    }
    return self;
}

+(instancetype)effect
{
    return [[self alloc] init];
}

@end

