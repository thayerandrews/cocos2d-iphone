//
//  CCEffectContrast.m
//  cocos2d-ios
//
//  Created by Thayer J Andrews on 5/7/14.
//
//

#import "CCEffectContrast.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"
#import "CCEffect_Private.h"
#import "CCRenderer.h"
#import "CCSetup.h"
#import "CCTexture.h"

static float conditionContrast(float contrast);

@interface CCEffectContrast ()
@property (nonatomic, strong) NSNumber *conditionedContrast;
@end


#pragma mark - CCEffectContrastImplGL

@interface CCEffectContrastImplGL : CCEffectImpl
@property (nonatomic, weak) CCEffectContrast *interface;
@end


@implementation CCEffectContrastImplGL

-(id)initWithInterface:(CCEffectContrast *)interface
{
    NSArray *renderPasses = [CCEffectContrastImplGL buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectContrastImplGL buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectContrastImplGL";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectContrastImplGL fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectContrastImplGL buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"contrast" inputs:@{@"inputValue" : @"tmp"}]];
    
    NSArray *uniforms = @[
                          [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"float" name:@"u_contrast" value:[NSNumber numberWithFloat:1.0f]]
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
                                   vec3 offset = vec3(0.5) * inputValue.a;
                                   return vec4(((inputValue.rgb - offset) * vec3(u_contrast) + offset), inputValue.a);
                                   );
    
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"contrastEffect" body:effectBody inputs:@[input] returnType:@"vec4"];
    return @[fragmentFunction];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectContrast *)interface
{
    __weak CCEffectContrast *weakInterface = interface;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectContrast pass 0";
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];

        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_contrast"]] = weakInterface.conditionedContrast;
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectContrastImplMetal

@interface CCEffectContrastImplMetal : CCEffectImpl
@property (nonatomic, weak) CCEffectContrast *interface;
@end


@implementation CCEffectContrastImplMetal

-(id)initWithInterface:(CCEffectContrast *)interface
{
    NSArray *renderPasses = [CCEffectContrastImplMetal buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectContrastImplMetal buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectContrastImplMetal";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderMetal defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectContrastImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectContrastImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"contrastAdjusted" inputs:@{@"contrast" : @"contrast",
                                                                                                                           @"inputValue" : @"tmp"}]];
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device float&" name:@"contrast" qualifier:CCEffectShaderArgumentBuffer]
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
                                   half3 offset = half3(0.5) * inputValue.a;
                                   return half4(((inputValue.rgb - offset) * half3(contrast) + offset), inputValue.a);
                                   );
    
    NSArray *inputs = @[
                        [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"],
                        [[CCEffectFunctionInput alloc] initWithType:@"const device float&" name:@"contrast"],
                        ];
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"contrastEffect"
                                                                           body:effectBody
                                                                         inputs:inputs
                                                                     returnType:@"half4"];
    
    return @[fragmentFunction];

}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectContrast *)interface
{
    __weak CCEffectContrast *weakInterface = interface;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectContrast pass 0";
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
                
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        CCEffectTexCoordDimensions tcDims;
        tcDims.texCoord1Center = passInputs.texCoord1Center;
        tcDims.texCoord1Extents = passInputs.texCoord1Extents;
        tcDims.texCoord2Center = passInputs.texCoord2Center;
        tcDims.texCoord2Extents = passInputs.texCoord2Extents;
        passInputs.shaderUniforms[CCShaderArgumentTexCoordDimensions] = [NSValue valueWithBytes:&tcDims objCType:@encode(CCEffectTexCoordDimensions)];
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"contrast"]] = weakInterface.conditionedContrast;

    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectContrast

@implementation CCEffectContrast

-(id)init
{
    return [self initWithContrast:0.0f];
}

-(id)initWithContrast:(float)contrast
{
    if((self = [super init]))
    {
        _contrast = contrast;
        _conditionedContrast = [NSNumber numberWithFloat:conditionContrast(contrast)];

        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectContrastImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectContrastImplGL alloc] initWithInterface:self];
        }
        
        self.debugName = @"CCEffectContrast";
    }
    return self;
}

+(instancetype)effectWithContrast:(float)contrast
{
    return [[self alloc] initWithContrast:contrast];
}

-(void)setContrast:(float)contrast
{
    _contrast = contrast;
    _conditionedContrast = [NSNumber numberWithFloat:conditionContrast(contrast)];
}

@end


float conditionContrast(float contrast)
{
    NSCAssert((contrast >= -1.0) && (contrast <= 1.0), @"Supplied contrast out of range [-1..1].");

    // Yes, this value is somewhat magical. It was arrived at experimentally by comparing
    // our results at min and max contrast (-1 and 1 respectively) with the results from
    // various image editing applications at their own min and max contrast values.
    static const float kContrastBase = 4.0f;
    
    float clampedExp = clampf(contrast, -1.0f, 1.0f);
    return powf(kContrastBase, clampedExp);
}
