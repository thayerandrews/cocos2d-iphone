//
//  CCEffectColorChannelOffset.m
//  cocos2d-ios
//
//  Created by Thayer J Andrews on 8/19/14.
//
//

#import "CCEffectColorChannelOffset.h"
#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffectShaderBuilderMetal.h"
#import "CCEffect_Private.h"
#import "CCRenderer.h"
#import "CCSetup.h"
#import "CCTexture.h"


#pragma mark - CCEffectColorChannelOffsetImplGL

@interface CCEffectColorChannelOffsetImplGL : CCEffectImpl

@property (nonatomic, weak) CCEffectColorChannelOffset *interface;

@end


@implementation CCEffectColorChannelOffsetImplGL

-(id)initWithInterface:(CCEffectColorChannelOffset *)interface
{
    NSArray *renderPasses = [CCEffectColorChannelOffsetImplGL buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectColorChannelOffsetImplGL buildShaders];

    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectColorChannelOffsetImplGL";
        self.stitchFlags = CCEffectFunctionStitchAfter;
    }
    
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectColorChannelOffsetImplGL fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectColorChannelOffsetImplGL buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitFragColor]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"colorChannelOffset" inputs:@{@"inputValue" : @"tmp"}]];
    
    NSArray *uniforms = @[
                          [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:@"u_redOffset" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:@"u_greenOffset" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:@"u_blueOffset" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]]
                          ];
    
    return [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                               functions:[[CCEffectShaderBuilderGL defaultFragmentFunctions] arrayByAddingObjectsFromArray:functions]
                                                   calls:calls
                                             temporaries:temporaries
                                                uniforms:uniforms
                                                varyings:@[]];
}

+ (NSArray *)buildFragmentFunctions
{
    CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"vec4" name:@"inputValue"];

    // Image pixellation shader based on pixellation filter in GPUImage - https://github.com/BradLarson/GPUImage
    NSString* effectBody = CC_GLSL(
                                   vec4 redSample   = inputValue * CCEffectSampleWithBounds(cc_FragTexCoord1 + u_redOffset,
                                                                                            cc_FragTexCoord1Center,
                                                                                            cc_FragTexCoord1Extents,
                                                                                            cc_PreviousPassTexture);
                                   
                                   vec4 greenSample = inputValue * CCEffectSampleWithBounds(cc_FragTexCoord1 + u_greenOffset,
                                                                                            cc_FragTexCoord1Center,
                                                                                            cc_FragTexCoord1Extents,
                                                                                            cc_PreviousPassTexture);
                                   
                                   vec4 blueSample  = inputValue * CCEffectSampleWithBounds(cc_FragTexCoord1 + u_blueOffset,
                                                                                            cc_FragTexCoord1Center,
                                                                                            cc_FragTexCoord1Extents,
                                                                                            cc_PreviousPassTexture);

                                   return vec4(redSample.r, greenSample.g, blueSample.b, max(max(redSample.a, greenSample.a), blueSample.a));
                                   );
    
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"colorChannelOffsetEffect" body:effectBody inputs:@[input] returnType:@"vec4"];
    return @[fragmentFunction];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectColorChannelOffset *)interface
{
    __weak CCEffectColorChannelOffset *weakInterface = interface;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectColorChannelOffset pass 0";
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Center] = [NSValue valueWithGLKVector2:passInputs.texCoord1Center];
        passInputs.shaderUniforms[CCShaderUniformTexCoord1Extents] = [NSValue valueWithGLKVector2:passInputs.texCoord1Extents];
        
        GLKVector2 scale = GLKVector2Make(-1.0f / passInputs.previousPassTexture.contentSize.width, -1.0f / passInputs.previousPassTexture.contentSize.height);
        CGPoint redOffsetUV = weakInterface.redOffset;
        CGPoint greenOffsetUV = weakInterface.greenOffset;
        CGPoint blueOffsetUV = weakInterface.blueOffset;
			
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_redOffset"]] = [NSValue valueWithGLKVector2:GLKVector2Make(redOffsetUV.x * scale.x, redOffsetUV.y * scale.y)];
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_greenOffset"]] = [NSValue valueWithGLKVector2:GLKVector2Make(greenOffsetUV.x * scale.x, greenOffsetUV.y * scale.y)];
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_blueOffset"]] = [NSValue valueWithGLKVector2:GLKVector2Make(blueOffsetUV.x * scale.x, blueOffsetUV.y * scale.y)];
        
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectColorChannelOffsetImplMetal

typedef struct CCEffectColorChannelOffsetParameters
{
    GLKVector2 redOffset;
    GLKVector2 greenOffset;
    GLKVector2 blueOffset;
} CCEffectColorChannelOffsetParameters;


@interface CCEffectColorChannelOffsetImplMetal : CCEffectImpl

@property (nonatomic, weak) CCEffectColorChannelOffset *interface;

@end


@implementation CCEffectColorChannelOffsetImplMetal

-(id)initWithInterface:(CCEffectColorChannelOffset *)interface
{
    NSArray *renderPasses = [CCEffectColorChannelOffsetImplMetal buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectColorChannelOffsetImplMetal buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectColorChannelOffsetImplMetal";
        self.stitchFlags = CCEffectFunctionStitchAfter;
    }
    
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderMetal defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectColorChannelOffsetImplMetal fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectColorChannelOffsetImplMetal buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"half4" name:@"tmp" initializer:CCEffectInitFragColor]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"colorOffset" inputs:@{@"cc_FragIn" : @"cc_FragIn",
                                                                                                                      @"cc_PreviousPassTexture" : @"cc_PreviousPassTexture",
                                                                                                                      @"cc_PreviousPassTextureSampler" : @"cc_PreviousPassTextureSampler",
                                                                                                                      @"cc_FragTexCoordDimensions" : @"cc_FragTexCoordDimensions",
                                                                                                                      @"offsets" : @"offsets",
                                                                                                                      @"inputValue" : @"tmp"
                                                                                                                      }]];
    NSArray *arguments = @[
                           [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectColorChannelOffsetParameters*" name:@"offsets" qualifier:CCEffectShaderArgumentBuffer]
                           ];

    NSString* structOffsets =
    @"float2 redOffset;\n"
    @"float2 greenOffset;\n"
    @"float2 blueOffset;\n";
    
    NSArray *structs = @[
                         [[CCEffectShaderStructDeclaration alloc] initWithName:@"CCEffectColorChannelOffsetParameters" body:structOffsets]
                         ];
    
    return [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderFragment
                                                  functions:[[CCEffectShaderBuilderMetal defaultFragmentFunctions] arrayByAddingObjectsFromArray:functions]
                                                      calls:calls
                                                temporaries:temporaries
                                                  arguments:[[CCEffectShaderBuilderMetal defaultFragmentArguments] arrayByAddingObjectsFromArray:arguments]
                                                    structs:[[CCEffectShaderBuilderMetal defaultStructDeclarations] arrayByAddingObjectsFromArray:structs]];
}

+ (NSArray *)buildFragmentFunctions
{
    NSArray *effectInputs = @[
                              [[CCEffectFunctionInput alloc] initWithType:@"const CCFragData" name:CCShaderArgumentFragIn],
                              [[CCEffectFunctionInput alloc] initWithType:@"texture2d<half>" name:CCShaderUniformPreviousPassTexture],
                              [[CCEffectFunctionInput alloc] initWithType:@"sampler" name:CCShaderUniformPreviousPassTextureSampler],
                              [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions],
                              [[CCEffectFunctionInput alloc] initWithType:@"const device CCEffectColorChannelOffsetParameters*" name:@"offsets"],
                              [[CCEffectFunctionInput alloc] initWithType:@"half4" name:@"inputValue"]
                              ];
    NSString *effectBody = CC_GLSL(
                                   half4 redSample = inputValue * CCEffectSampleWithBounds(cc_FragIn.texCoord1 + offsets->redOffset,
                                                                                           cc_FragTexCoordDimensions->texCoord1Center,
                                                                                           cc_FragTexCoordDimensions->texCoord1Extents,
                                                                                           cc_PreviousPassTexture,
                                                                                           cc_PreviousPassTextureSampler);
                                   
                                   half4 greenSample = inputValue * CCEffectSampleWithBounds(cc_FragIn.texCoord1 + offsets->greenOffset,
                                                                                             cc_FragTexCoordDimensions->texCoord1Center,
                                                                                             cc_FragTexCoordDimensions->texCoord1Extents,
                                                                                             cc_PreviousPassTexture,
                                                                                             cc_PreviousPassTextureSampler);
                                   
                                   half4 blueSample = inputValue * CCEffectSampleWithBounds(cc_FragIn.texCoord1 + offsets->blueOffset,
                                                                                            cc_FragTexCoordDimensions->texCoord1Center,
                                                                                            cc_FragTexCoordDimensions->texCoord1Extents,
                                                                                            cc_PreviousPassTexture,
                                                                                            cc_PreviousPassTextureSampler);
                                   
                                   return half4(redSample.r, greenSample.g, blueSample.b, max(max(redSample.a, greenSample.a), blueSample.a));
                                   );
    return @[[[CCEffectFunction alloc] initWithName:@"colorChannelOffset" body:effectBody inputs:effectInputs returnType:@"half4"]];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectColorChannelOffset *)interface
{
    __weak CCEffectColorChannelOffset *weakInterface = interface;
    
    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectColorChannelOffset pass 0";
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
        
        GLKVector2 scale = GLKVector2Make(-1.0f / passInputs.previousPassTexture.contentSize.width, -1.0f / passInputs.previousPassTexture.contentSize.height);
        CGPoint redOffsetUV = weakInterface.redOffset;
        CGPoint greenOffsetUV = weakInterface.greenOffset;
        CGPoint blueOffsetUV = weakInterface.blueOffset;

        CCEffectColorChannelOffsetParameters parameters;
        parameters.redOffset = GLKVector2Make(redOffsetUV.x * scale.x, redOffsetUV.y * scale.y);
        parameters.greenOffset = GLKVector2Make(greenOffsetUV.x * scale.x, greenOffsetUV.y * scale.y);
        parameters.blueOffset = GLKVector2Make(blueOffsetUV.x * scale.x, blueOffsetUV.y * scale.y);
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"offsets"]] = [NSValue valueWithBytes:&parameters objCType:@encode(CCEffectColorChannelOffsetParameters)];
        
    }]];
    
    return @[pass0];
}

@end


#pragma mark - CCEffectColorChannelOffset

@implementation CCEffectColorChannelOffset

-(id)init
{
    return [self initWithRedOffset:CGPointZero greenOffset:CGPointZero blueOffset:CGPointZero];
}

-(id)initWithRedOffset:(CGPoint)redOffset greenOffset:(CGPoint)greenOffset blueOffset:(CGPoint)blueOffset
{    
    if((self = [super init]))
    {
        _redOffset = redOffset;
        _greenOffset = greenOffset;
        _blueOffset = blueOffset;
        
        if([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIMetal)
        {
            self.effectImpl = [[CCEffectColorChannelOffsetImplMetal alloc] initWithInterface:self];
        }
        else
        {
            self.effectImpl = [[CCEffectColorChannelOffsetImplGL alloc] initWithInterface:self];
        }
        self.debugName = @"CCEffectColorChannelOffset";
    }
    
    return self;
}

+(instancetype)effectWithRedOffset:(CGPoint)redOffset greenOffset:(CGPoint)greenOffset blueOffset:(CGPoint)blueOffset
{
    return [[self alloc] initWithRedOffset:redOffset greenOffset:greenOffset blueOffset:blueOffset];
}

- (CGPoint)redOffsetWithPoint
{
    return CGPointMake(_redOffset.x, _redOffset.y);
}

@end

