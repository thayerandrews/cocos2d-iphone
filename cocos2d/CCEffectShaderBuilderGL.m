//
//  CCEffectShaderBuilderGL.m
//  cocos2d
//
//  Created by Thayer J Andrews on 3/23/15.
//
//

#import "CCEffectShaderBuilderGL.h"
#import "CCEffectFunction.h"
#import "CCEffectUniform.h"
#import "CCEffectVarying.h"
#import "CCEffect_Private.h"
#import "CCSetup.h"


static NSString * const vtxTemplate =
@"    cc_FragColor = cc_Color;\n"
@"    cc_FragTexCoord1 = cc_TexCoord1;\n"
@"    cc_FragTexCoord2 = cc_TexCoord2;\n"
@"    gl_Position = %@;\n";

static NSString * const fragTemplate =
@"    gl_FragColor = %@;\n";

@interface CCEffectShaderBuilderGL ()

@property (nonatomic, strong) NSString *cachedShaderSource;

@end


@implementation CCEffectShaderBuilderGL

- (id)initWithType:(CCEffectShaderBuilderType)type functions:(NSArray *)functions calls:(NSArray *)calls temporaries:(NSArray *)temporaries uniforms:(NSArray *)uniforms varyings:(NSArray *)varyings
{
    NSAssert([CCSetup sharedSetup].graphicsAPI == CCGraphicsAPIGL, @"You're constructing a GL shader builder but the current graphics API is not GL.");
    NSAssert(functions, @"");
    NSAssert(calls, @"");
    
    if((self = [super initWithType:type functions:functions calls:calls temporaries:temporaries]))
    {
        _cachedShaderSource = nil;
        
        _uniforms = [uniforms copy];
        _varyings = [varyings copy];
        
        for(CCEffectFunctionTemporary *temporary in self.temporaries)
        {
            NSAssert([temporary isKindOfClass:[CCEffectFunctionTemporaryGL class]], @"Supplied temporary is not a GL temporary.");
            NSAssert(((type == CCEffectShaderBuilderVertex) && temporary.isValidForVertexShader) ||
                     ((type == CCEffectShaderBuilderFragment) && temporary.isValidForFragmentShader),
                     @"The temporary's initializer does not match the shader type.");
        }
        
        // Error check the supplied uniforms.
        for(CCEffectUniform *uniform in uniforms)
        {
            NSAssert([uniform isKindOfClass:[CCEffectUniform class]], @"Expected a CCEffectUniform and found something else.");
        }
        
        // Error check the supplied varyings.
        for(CCEffectVarying *varying in varyings)
        {
            NSAssert([varying isKindOfClass:[CCEffectVarying class]], @"Expected a CCEffectVarying and found something else.");
        }
    }
    return self;
}

- (NSString *)shaderSource
{
    if (!_cachedShaderSource)
    {
        NSString *template = vtxTemplate;
        if (self.type == CCEffectShaderBuilderFragment)
        {
            template = fragTemplate;
        }
        _cachedShaderSource = [CCEffectShaderBuilderGL buildShaderSourceOfType:self.type functions:self.functions calls:self.calls temporaries:self.temporaries uniforms:self.uniforms varyings:self.varyings];
    }
    
    return _cachedShaderSource;
}

- (NSArray *)parameters
{
    return _uniforms;
}

+ (NSSet *)defaultUniformNames
{
    return [[NSSet alloc] initWithArray:@[
                                          CCShaderUniformPreviousPassTexture,
                                          CCShaderUniformTexCoord1Center,
                                          CCShaderUniformTexCoord1Extents,
                                          CCShaderUniformTexCoord2Center,
                                          CCShaderUniformTexCoord2Extents
                                          ]];
}

+ (NSArray *)defaultFragmentFunctions
{
    NSArray *sampleWithBoundsInputs = @[
                                        [[CCEffectFunctionInput alloc] initWithType:@"vec2" name:@"texCoord"],
                                        [[CCEffectFunctionInput alloc] initWithType:@"vec2" name:@"texCoordCenter"],
                                        [[CCEffectFunctionInput alloc] initWithType:@"vec2" name:@"texCoordExtents"],
                                        [[CCEffectFunctionInput alloc] initWithType:@"sampler2D" name:@"inputTexture"],
                                        ];
    NSString *sampleWithBoundsBody = CC_GLSL(
                                             vec2 compare = texCoordExtents - abs(texCoord - texCoordCenter);
                                             float inBounds = step(0.0, min(compare.x, compare.y));
                                             return texture2D(inputTexture, texCoord) * inBounds;
                                             );
    CCEffectFunction* sampleWithBoundsFunction = [[CCEffectFunction alloc] initWithName:@"CCEffectSampleWithBounds" body:sampleWithBoundsBody inputs:sampleWithBoundsInputs returnType:@"vec4"];
    
    return @[sampleWithBoundsFunction];
}

+ (CCEffectShaderBuilder *)defaultVertexShaderBuilder
{
    static dispatch_once_t once;
    static CCEffectShaderBuilder *builder = nil;
    dispatch_once(&once, ^{
        
        NSString* body = CC_GLSL(
                                 return cc_Position;
                                 );
        
        CCEffectFunction *function = [[CCEffectFunction alloc] initWithName:@"defaultVShader"
                                                                       body:body
                                                                     inputs:nil
                                                                 returnType:@"vec4"];
        CCEffectFunctionCall *call = [[CCEffectFunctionCall alloc] initWithFunction:function outputName:@"position" inputs:nil];
        
        builder = [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderVertex
                                                      functions:@[function]
                                                          calls:@[call]
                                                    temporaries:@[]
                                                       uniforms:@[]
                                                       varyings:@[]];
    });
    return builder;
}


+ (NSString *)buildShaderSourceOfType:(CCEffectShaderBuilderType)type functions:(NSArray *)functions calls:(NSArray *)calls temporaries:(NSArray *)temporaries uniforms:(NSArray *)uniforms varyings:(NSArray *)varyings
{
    NSString *template = vtxTemplate;
    if (type == CCEffectShaderBuilderFragment)
    {
        template = fragTemplate;
    }
    
    NSMutableString *shaderString = [[NSMutableString alloc] initWithString:@"\n//\n// Source generated by CCEffectShaderBuilder.\n//\n\n"];
    
    // Output uniforms
    [shaderString appendString:@"\n// Uniform variables\n"];
    for(CCEffectUniform* uniform in uniforms)
    {
        [shaderString appendFormat:@"%@\n", uniform.declaration];
    }
    
    // Output varyings
    [shaderString appendString:@"\n// Varying variables\n"];
    for(CCEffectVarying* varying in varyings)
    {
        [shaderString appendFormat:@"%@\n", varying.declaration];
    }
    
    // Output function declarations
    [shaderString appendString:@"\n// Function declarations\n\n"];
    for(CCEffectFunction* function in functions)
    {
        [shaderString appendFormat:@"%@;\n", function.declaration];
    }
    [shaderString appendString:@"\n"];
    
    // Output function definitions
    [shaderString appendString:@"\n// Function definitions\n\n"];
    for(CCEffectFunction* function in functions)
    {
        [shaderString appendFormat:@"%@\n\n", function.definition];
    }
    [shaderString appendString:@"\n"];
    
    // Output main
    [shaderString appendString:@"void main ()\n{\n"];
    
    // Put all temporaries in a dictionary of allocated variables so we can check
    // them as possible input sources below.
    NSMutableDictionary *allocatedTemps = [[NSMutableDictionary alloc] init];
    for(CCEffectFunctionTemporary *temporary in temporaries)
    {
        NSAssert(!allocatedTemps[temporary.name], @"Redeclaration of temporary variable.");        
        allocatedTemps[temporary.name] = temporary.type;
        [shaderString appendFormat:@"    %@;\n", temporary.declaration];
    }
    [shaderString appendString:@"\n"];
    
    for(CCEffectFunctionCall* call in calls)
    {
        // Check to make sure all the inputs are valid before proceeding.
        [CCEffectShaderBuilderGL checkTemporaries:allocatedTemps forFunction:call.function withInputMapping:call.inputs];
        
        // Allocate a temporary to hold this call's output if one is needed.
        if (!allocatedTemps[call.outputName])
        {
            // Generate the call string and assignment of the result to the temporary (with variable declaration).
            [shaderString appendFormat:@"    %@ %@ = %@;\n", call.function.returnType, call.outputName, [call.function callStringWithInputMappings:call.inputs]];
        }
        else
        {
            // Generate the call string and assignment of the result to the temporary.
            [shaderString appendFormat:@"    %@ = %@;\n", call.outputName, [call.function callStringWithInputMappings:call.inputs]];
        }
        
        // Be sure to add the call's output variable to the allocated temporaries
        // dictionary so: a) It's not redeclared later and b) it's available for use
        // as an input in subsequent calls.
        allocatedTemps[call.outputName] = call.function.returnType;
    }
    [shaderString appendString:@"\n"];
    
    CCEffectFunctionCall* lastCall = [calls lastObject];
    [shaderString appendFormat:template, lastCall.outputName];
    
    [shaderString appendString:@"}\n"];
    
    return shaderString;
}

+ (void)checkTemporaries:(NSDictionary *)allocatedTemps forFunction:(CCEffectFunction *)function withInputMapping:(NSDictionary *)inputMapping
{
    for (CCEffectFunctionInput  *input in function.inputs)
    {
        NSString *temporary = inputMapping[input.name];
        NSAssert(temporary, @"No temporary was assigned to the function's input.");
        
        NSString *type = allocatedTemps[temporary];
        NSAssert(type, @"No temporary exists for the input assignment.");
        
        NSAssert([input.type isEqualToString:type], @"Type mismatch on assignment of temporary to function input.");
    }
}

@end
