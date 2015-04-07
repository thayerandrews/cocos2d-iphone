//
//  CCEffectBrightness.m
//  cocos2d-ios
//
//  Created by Thayer J Andrews on 5/7/14.
//
//

#import "CCEffectBrightness.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"
#import "CCEffect_Private.h"
#import "CCRenderer.h"
#import "CCSetup.h"
#import "CCTexture.h"

static float conditionBrightness(float brightness);

@interface CCEffectBrightness ()
@property (nonatomic, strong) NSNumber *conditionedBrightness;
@end


#pragma mark - CCEffectBrighnessImplGL

@interface CCEffectBrightnessImplGL : CCEffectImpl
@property (nonatomic, weak) CCEffectBrightness *interface;
@end


@implementation CCEffectBrightnessImplGL

-(id)initWithInterface:(CCEffectBrightness *)interface
{
    NSArray *renderPasses = [CCEffectBrightnessImplGL buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectBrightnessImplGL buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectBrightnessImplGL";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectBrightnessImplGL fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectBrightnessImplGL buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"brightness" inputs:@{@"inputValue" : @"tmp"}]];
    
    NSArray *uniforms = @[
                          [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"float" name:@"u_brightness" value:[NSNumber numberWithFloat:0.0f]]
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

    NSString* effectBody = CC_GLSL(
                                   return vec4((inputValue.rgb + vec3(u_brightness * inputValue.a)), inputValue.a);
                                   );
    
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"brightnessEffect" body:effectBody inputs:@[input] returnType:@"vec4"];
    return @[fragmentFunction];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectBrightness *)interface
{
    __weak CCEffectBrightness *weakInterface = interface;

    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectBrightness pass 0";
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];

        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_brightness"]] = weakInterface.conditionedBrightness;
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectBrighnessImplMetal

@interface CCEffectBrightnessImplMetal : CCEffectImpl
@property (nonatomic, weak) CCEffectBrightness *interface;
@end


@implementation CCEffectBrightnessImplMetal

-(id)initWithInterface:(CCEffectBrightness *)interface
{
    NSArray *renderPasses = [CCEffectBrightnessImplMetal buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectBrightnessImplMetal buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectBrightnessImplMetal";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderMetal defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectBrightnessImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectBrightnessImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"BrightnessAdjusted" inputs:@{@"brightness" : @"brightness",
                                                                                                                             @"inputValue" : @"tmp"}]];
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device float&" name:@"brightness" qualifier:CCEffectShaderArgumentBuffer]
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
                                   return half4((inputValue.rgb + half3(brightness * inputValue.a)), inputValue.a);
                                   );
    
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device float&" name:@"brightness"],
                        ];
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"brightnessEffect"
                                                                           body:effectBody
                                                                         inputs:inputs
                                                                     returnType:@"half4"];
    
    return @[fragmentFunction];
    
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectBrightness *)interface
{
    __weak CCEffectBrightness *weakInterface = interface;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectBrightness pass 0";
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"brightness"]] = weakInterface.conditionedBrightness;
        
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectBrightness

@implementation CCEffectBrightness

-(id)init
{
    return [self initWithBrightness:0.0f];
}

-(id)initWithBrightness:(float)brightness
{
    if((self = [super init]))
    {
        _brightness = brightness;
        _conditionedBrightness = [NSNumber numberWithFloat:conditionBrightness(brightness)];

        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectBrightnessImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectBrightnessImplGL alloc] initWithInterface:self];
        }
        
        self.debugName = @"CCEffectBrightness";
    }
    return self;
}

+(instancetype)effectWithBrightness:(float)brightness
{
    return [[self alloc] initWithBrightness:brightness];
}

-(void)setBrightness:(float)brightness
{
    _brightness = brightness;
    _conditionedBrightness = [NSNumber numberWithFloat:conditionBrightness(brightness)];
}

@end



float conditionBrightness(float brightness)
{
    NSCAssert((brightness >= -1.0) && (brightness <= 1.0), @"Supplied brightness out of range [-1..1].");
    return clampf(brightness, -1.0f, 1.0f);
}
