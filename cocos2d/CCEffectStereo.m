//
//  CCEffectStereo.m
//  cocos2d
//
//  Created by Thayer J Andrews on 3/16/15.
//
//

#import "CCEffectStereo.h"

#if CC_EFFECTS_EXPERIMENTAL

#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"
#import "CCEffect_Private.h"
#import "CCRenderer.h"
#import "CCSetup.h"
#import "CCTexture.h"


#pragma mark - CCEffectSteroImplGL

@interface CCEffectStereoImplGL : CCEffectImpl
@property (nonatomic, weak) CCEffectStereo *interface;
@end

@implementation CCEffectStereoImplGL

-(id)initWithInterface:(CCEffectStereo *)interface
{
    NSArray *renderPasses = [CCEffectStereoImplGL buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectStereoImplGL buildShaders];
    
    if((self = [super initWithRenderPassDescriptors:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectStereoImpl";
        self.stitchFlags = CCEffectFunctionStitchAfter;
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectStereoImplGL fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectStereoImplGL buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"stereoOffset" inputs:@{@"inputValue" : @"tmp"}]];
    
    NSArray *uniforms = @[
                          [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"float" name:@"u_channelSelect" value:[NSNumber numberWithFloat:0.0f]]
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
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];
    
    NSString* effectPrefix =
    @"#ifdef GL_ES\n"
    @"#ifdef GL_EXT_shader_framebuffer_fetch\n"
    @"#extension GL_EXT_shader_framebuffer_fetch : enable\n"
    @"#endif\n"
    @"#endif\n";
    
    NSString* effectBody = CC_GLSL(
                                   vec4 result;
                                   vec4 fbPixel = gl_LastFragData[0];
                                   float dstAlpha = 1.0 - inputValue.a;
                                   
                                   if (u_channelSelect == 0.0)
                                   {
                                       result = vec4(inputValue.r + fbPixel.r * dstAlpha, fbPixel.g, fbPixel.b, 1);
                                   }
                                   else
                                   {
                                       result = vec4(fbPixel.r, inputValue.g + fbPixel.g * dstAlpha, inputValue.b + fbPixel.b * dstAlpha, 1);
                                   }
                                   return result;
                                   );
    
    return @[[[CCEffectFunction alloc] initWithName:@"stereoEffect" body:[effectPrefix stringByAppendingString:effectBody] inputs:@[input] returnType:@"vec4"]];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectStereo *)interface
{
    __weak CCEffectStereo *weakInterface = interface;
    
    CCEffectRenderPassDescriptor *pass0 = [CCEffectRenderPassDescriptor descriptor];
    pass0.debugLabel = @"CCEffectPixellate pass 0";
    pass0.blendMode = [CCBlendMode disabledMode];
    pass0.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_channelSelect"]] = (interface.channelSelect == CCEffectStereoSelectRed) ? @(0.0f) : @(1.0f);
        
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectStereoImplMetal

@interface CCEffectStereoImplMetal : CCEffectImpl
@property (nonatomic, weak) CCEffectStereo *interface;
@end


@implementation CCEffectStereoImplMetal

-(id)initWithInterface:(CCEffectStereo *)interface
{
    NSArray *renderPasses = [CCEffectStereoImplMetal buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectStereoImplMetal buildShaders];
    
    if((self = [super initWithRenderPassDescriptors:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectStereoImplMetal";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderMetal defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectStereoImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectStereoImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[
                             [CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitPreviousPass],
                             [CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"dstColor" initializer:CCEffectInitFragColor]
                             ];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"stereoSeparated" inputs:@{@"channelSelect" : @"channelSelect",
                                                                                                                          @"dstColor" : @"dstColor",
                                                                                                                          @"inputValue" : @"tmp"}]];
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device float&" name:@"channelSelect" qualifier:CCEffectShaderArgumentBuffer],

// XXX The following should work but currently results in a Metal pipeline state that won't compile. My
// guess is that the associated state for color attachment 0 needs to be adjusted somehow to support
// shader reads from it. Since this is an experimental effect anyway, I'm leaving the investigation until
// after I've implemented the remainder of the non-experimental effects.
//
//                           [[CCEffectShaderArgument alloc] initWithType:@"half4" name:@"dstColor" qualifier:CCEffectShaderArgumentDstColor]
                           ];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                  functions:functions
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:[[CCEffectShaderBuilderMetal defaultFragmentArguments] arrayByAddingObjectsFromArray:arguments]
                                                    structs:[CCEffectShaderBuilderMetal defaultStructDeclarations]];
}

+ (NSArray *)buildFragmentFunctions
{
    NSString* effectBody = CC_GLSL(
                                   half4 result;
                                   float dstAlpha = 1.0 - inputValue.a;

                                   if (channelSelect == 0.0)
                                   {
                                       result = half4(inputValue.r + dstColor.r * dstAlpha, dstColor.g, dstColor.b, 1);
                                   }
                                   else
                                   {
                                       result = half4(dstColor.r, inputValue.g + dstColor.g * dstAlpha, inputValue.b + dstColor.b * dstAlpha, 1);
                                   }
                                   return result;
                                   );
    
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"],
                        [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"dstColor"],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device float&" name:@"channelSelect"],
                        ];
    return @[[[CCEffectFunction alloc] initWithName:@"stereoEffect" body:effectBody inputs:inputs returnType:@"half4"]];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectStereo *)interface
{
    __weak CCEffectStereo *weakInterface = interface;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectStereo pass 0";
    pass0.beginBlocks = @[[[CCEffectBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"channelSelect"]] = (interface.channelSelect == CCEffectStereoSelectRed) ? @(0.0f) : @(1.0f);
        
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectStero

@implementation CCEffectStereo

-(id)init
{
    return [self initWithChannelSelect:CCEffectStereoSelectRed];
}

-(id)initWithChannelSelect:(CCEffectStereoChannelSelect)channelSelect
{
    if((self = [super init]))
    {
        _channelSelect = channelSelect;
        
        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectStereoImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectStereoImplGL alloc] initWithInterface:self];
        }

        self.debugName = @"CCEffectStereo";
    }
    
    return self;
}

+(instancetype)effectWithChannelSelect:(CCEffectStereoChannelSelect)channelSelect
{
    return [[self alloc] initWithChannelSelect:channelSelect];
}

@end

#endif

