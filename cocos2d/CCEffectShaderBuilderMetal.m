//
//  CCEffectShaderBuilderMetal.m
//  cocos2d
//
//  Created by Thayer J Andrews on 3/24/15.
//
//

#import "CCEffectShaderBuilderMetal.h"
#import "CCEffectFunction.h"
#import "CCEffect_Private.h"


static NSString * const vtxTemplate =
@"vertex %@ ShaderMain(\n"
@"%@"
@")\n"
@"{\n"
@"%@\n"
@"    return %@;\n"
@"}\n";

static NSString * const fragTemplate =
@"fragment %@ ShaderMain(\n"
@"%@"
@")\n"
@"{\n"
@"    half4 out;\n"
@"%@\n"
@"    out = %@;\n"
@"    return out;\n"
@"}\n";

static NSString * const CCEffectTexCoordDimensionsStruct = @"CCEffectTexCoordDimensions";


@interface CCEffectShaderBuilderMetal ()

@property (nonatomic, strong) NSString *cachedShaderSource;

@end


@implementation CCEffectShaderBuilderMetal

- (id)initWithType:(CCEffectShaderBuilderType)type functions:(NSArray *)functions calls:(NSArray *)calls temporaries:(NSArray *)temporaries arguments:(NSArray *)arguments structs:(NSArray *)structs
{
    NSAssert(functions, @"");
    NSAssert(calls, @"");
    
    if((self = [super initWithType:type functions:functions calls:calls temporaries:temporaries]))
    {
        _cachedShaderSource = nil;
        _arguments = [arguments copy];
        _structs = [structs copy];
    }
    return self;
}

- (NSString *)shaderSource
{
    if (!_cachedShaderSource)
    {
        _cachedShaderSource = [CCEffectShaderBuilderMetal buildShaderSourceOfType:self.type functions:self.functions calls:self.calls temporaries:self.temporaries arguments:self.arguments structs:self.structs];
    }
    
    return _cachedShaderSource;
}

- (NSArray *)parameters
{
    return _arguments;
}

+ (NSSet *)defaultVertexArgumentNames
{
    return [[NSSet alloc] initWithArray:@[
                                          CCShaderArgumentVertexId,
                                          CCShaderArgumentVertexAtttributes
                                          ]];
}

+ (NSArray *)defaultVertexArguments
{
    return @[
             [[CCEffectShaderArgument alloc] initWithType:@"const device CCVertex*" name:CCShaderArgumentVertexAtttributes qualifier:CCEffectShaderArgumentBuffer],
             [[CCEffectShaderArgument alloc] initWithType:@"unsigned int" name:CCShaderArgumentVertexId qualifier:CCEffectShaderArgumentVertexId]
             ];
}

+ (NSSet *)defaultFragmentArgumentNames
{
    return [[NSSet alloc] initWithArray:@[
                                          CCShaderUniformMainTexture,
                                          CCShaderUniformMainTextureSampler,
                                          CCShaderUniformPreviousPassTexture,
                                          CCShaderUniformPreviousPassTextureSampler,
                                          CCShaderUniformNormalMapTexture,
                                          CCShaderUniformNormalMapTextureSampler,
                                          CCShaderArgumentFragIn,
                                          CCShaderArgumentTexCoordDimensions
                                          ]];
}

+ (NSArray *)defaultFragmentArguments
{
    return @[
             [[CCEffectShaderArgument alloc] initWithType:@"const CCFragData" name:CCShaderArgumentFragIn qualifier:CCEffectShaderArgumentStageIn],
             [[CCEffectShaderArgument alloc] initWithType:@"texture2d<half>" name:CCShaderUniformMainTexture qualifier:CCEffectShaderArgumentTexture],
             [[CCEffectShaderArgument alloc] initWithType:@"sampler" name:CCShaderUniformMainTextureSampler qualifier:CCEffectShaderArgumentSampler],
             [[CCEffectShaderArgument alloc] initWithType:@"texture2d<half>" name:CCShaderUniformPreviousPassTexture qualifier:CCEffectShaderArgumentTexture],
             [[CCEffectShaderArgument alloc] initWithType:@"sampler" name:CCShaderUniformPreviousPassTextureSampler qualifier:CCEffectShaderArgumentSampler],
             [[CCEffectShaderArgument alloc] initWithType:@"texture2d<half>" name:CCShaderUniformNormalMapTexture qualifier:CCEffectShaderArgumentTexture],
             [[CCEffectShaderArgument alloc] initWithType:@"sampler" name:CCShaderUniformNormalMapTextureSampler qualifier:CCEffectShaderArgumentSampler],
             [[CCEffectShaderArgument alloc] initWithType:@"const device CCEffectTexCoordDimensions*" name:CCShaderArgumentTexCoordDimensions qualifier:CCEffectShaderArgumentBuffer]
             ];
}

+ (NSSet *)defaultStructNames
{
    return [[NSSet alloc] initWithArray:@[
                                          @"CCVertex",
                                          @"CCFragData",
                                          @"CCGlobalUniforms",
                                          CCEffectTexCoordDimensionsStruct
                                          ]];
}

+ (NSArray *)defaultStructDeclarations
{
    NSString* structTexCoordDimensions =
    @"float2 texCoord1Center;\n"
    @"float2 texCoord1Extents;\n"
    @"float2 texCoord2Center;\n"
    @"float2 texCoord2Extents;\n";

    return @[
             [[CCEffectShaderStructDeclaration alloc] initWithName:CCEffectTexCoordDimensionsStruct body:structTexCoordDimensions]
             ];

}

+ (CCEffectShaderBuilder *)defaultVertexShaderBuilder
{
    static dispatch_once_t once;
    static CCEffectShaderBuilder *builder = nil;
    dispatch_once(&once, ^{
        
        NSString* body = CC_GLSL(
                                 return fragData;
                                 );
        
        CCEffectFunctionInput *input = [[CCEffectFunctionInput alloc] initWithType:@"CCFragData" name:@"fragData"];
        CCEffectFunction *function = [[CCEffectFunction alloc] initWithName:@"defaultVShader"
                                                                       body:body
                                                                     inputs:@[input]
                                                                 returnType:@"CCFragData"];
        CCEffectFunctionTemporary *temporary = [CCEffectFunctionTemporary temporaryWithType:@"CCFragData" name:@"tmp" initializer:CCEffectInitVertexAttributes];
        CCEffectFunctionCall *call = [[CCEffectFunctionCall alloc] initWithFunction:function outputName:@"out" inputs:@{ @"fragData" : @"tmp" }];
        
        builder = [[CCEffectShaderBuilderMetal alloc] initWithType:CCEffectShaderBuilderVertex
                                                         functions:@[function]
                                                             calls:@[call]
                                                       temporaries:@[temporary]
                                                         arguments:[CCEffectShaderBuilderMetal defaultVertexArguments]
                                                           structs:nil];
    });
    return builder;
}


+ (NSString *)buildShaderSourceOfType:(CCEffectShaderBuilderType)type functions:(NSArray *)functions calls:(NSArray *)calls temporaries:(NSArray *)temporaries arguments:(NSArray *)arguments structs:(NSArray *)structs
{
    NSString *template = vtxTemplate;
    if (type == CCEffectShaderBuilderFragment)
    {
        template = fragTemplate;
    }
    
    NSMutableString *shaderString = [[NSMutableString alloc] initWithString:@"\n//\n// Source generated by CCEffectShaderBuilder.\n//\n\n"];
    
    // Struct declarations
    [shaderString appendString:@"\n// Struct declarations\n\n"];
    for(CCEffectShaderStructDeclaration* structDecl in structs)
    {
        [shaderString appendFormat:@"%@;\n\n", structDecl.declaration];
    }
    [shaderString appendString:@"\n"];

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
    
    NSUInteger argumentCounts[CCEffectShaderArgumentQualifierCount];
    memset(&argumentCounts, 0, sizeof(argumentCounts));
    
    // Construct the argument string of the main function.
    NSMutableString *argumentString = [[NSMutableString alloc] init];
    for(CCEffectShaderArgument *argument in arguments)
    {
        [argumentString appendFormat:@"%@", [argument declarationAtLocation:argumentCounts[argument.qualifier]]];
        if (argument != [arguments lastObject])
        {
            [argumentString appendString:@",\n"];
        }
        argumentCounts[argument.qualifier]++;
    }
    
    NSAssert(((type == CCEffectShaderBuilderVertex) && (argumentCounts[CCEffectShaderArgumentStageIn] == 0)) ||
             ((type == CCEffectShaderBuilderFragment) && (argumentCounts[CCEffectShaderArgumentStageIn] == 1)),
             @"Vertex shaders can't have any stage_in arguments. Fragment shaders can only have one stage_in argument.");

    NSAssert(((type == CCEffectShaderBuilderVertex) && (argumentCounts[CCEffectShaderArgumentVertexId] == 1)) ||
             ((type == CCEffectShaderBuilderFragment) && (argumentCounts[CCEffectShaderArgumentVertexId] == 0)),
             @"Vertex shaders can have only one vertex_id argument. Fragment shaders can't have any vertex_id arguments.");

    
    // Construct the body of the main function.
    NSMutableString *bodyString = [[NSMutableString alloc] init];
    
    // Put all temporaries in a dictionary of allocated variables so we can check
    // them as possible input sources below.
    NSMutableDictionary *allocatedInputs = [[NSMutableDictionary alloc] init];
    for(CCEffectFunctionTemporary *temporary in temporaries)
    {
        NSAssert([temporary isKindOfClass:[CCEffectFunctionTemporaryMetal class]], @"Supplied temporary is not a GL temporary.");
        NSAssert(!allocatedInputs[temporary.name], @"Redeclaration of temporary variable.");
        NSAssert(((type == CCEffectShaderBuilderVertex) && temporary.isValidForVertexShader) ||
                 ((type == CCEffectShaderBuilderFragment) && temporary.isValidForFragmentShader),
                 @"The temporary's initializer does not match the shader type.");
        
        allocatedInputs[temporary.name] = temporary.type;
        [bodyString appendFormat:@"    %@;\n", temporary.declaration];
    }
    [bodyString appendString:@"\n"];

    for(CCEffectFunctionCall* call in calls)
    {
        // Check to make sure all the inputs are valid before proceeding.
        [CCEffectShaderBuilderMetal checkTemporaries:allocatedInputs forFunction:call.function withInputMapping:call.inputs];
        
        // Allocate a temporary to hold this call's output if one is needed.
        if (!allocatedInputs[call.outputName])
        {
            // Generate the call string and assignment of the result to the temporary (with variable declaration).
            [bodyString appendFormat:@"    %@ %@ = %@;\n", call.function.returnType, call.outputName, [call.function callStringWithInputMappings:call.inputs]];
        }
        else
        {
            // Generate the call string and assignment of the result to the temporary.
            [bodyString appendFormat:@"    %@ = %@;\n", call.outputName, [call.function callStringWithInputMappings:call.inputs]];
        }
        
        // Be sure to add the call's output variable to the allocated temporaries
        // dictionary so: a) It's not redeclared later and b) it's available for use
        // as an input in subsequent calls.
        allocatedInputs[call.outputName] = call.function.returnType;
    }
    
    CCEffectFunctionCall* lastCall = [calls lastObject];
    [shaderString appendFormat:template, lastCall.function.returnType, argumentString, bodyString, lastCall.outputName];
    
    return shaderString;
}

+ (void)checkTemporaries:(NSDictionary *)allocatedTemps forFunction:(CCEffectFunction *)function withInputMapping:(NSDictionary *)inputMapping
{
    for (CCEffectFunctionInput  *input in function.inputs)
    {
        NSString *temporary = inputMapping[input.name];
        NSAssert(temporary, @"No temporary was assigned to the function's input.");

        // XXX We should handle arguments and their types here.
//        NSString *type = allocatedTemps[temporary];
//        NSAssert(type, @"No temporary exists for the input assignment.");
//        
//        NSAssert([input.type isEqualToString:type], @"Type mismatch on assignment of temporary to function input.");
    }
}

@end





#pragma mark CCEffectShaderArgument

@implementation CCEffectShaderArgument

- (id)initWithType:(NSString *)type name:(NSString *)name qualifier:(CCEffectShaderArgumentQualifier)qualifier
{
    if((self = [super init]))
    {
        _name = [name copy];
        _type = [type copy];
        _qualifier = qualifier;
        
        // XXX In Metal, function arguments can represent the following GLSL primitives: vertex attributes,
        // varyings, and uniforms. Only arguments that represent uniforms (ie constant values) need to be
        // associated with NSValues. We need to make a subclass for these constant arguments (though that
        // complicates things slightly because the argument qualifier also comes into play).
        _value = [NSNumber numberWithFloat:3.33f];
    }
    
    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    // CCEffectShaderArgument is immutable so no need to really copy.
    // Just return self.
    return self;
}

- (NSString *)declarationAtLocation:(NSUInteger)location;
{
    if ((_qualifier == CCEffectShaderArgumentStageIn) ||
        (_qualifier == CCEffectShaderArgumentVertexId))
    {
        return [NSString stringWithFormat:@"%@ %@ [[ %@ ]]", _type, _name, [CCEffectShaderArgument stringWithQualifier:_qualifier]];
    }
    else
    {
        return [NSString stringWithFormat:@"%@ %@ [[ %@(%lu) ]]", _type, _name, [CCEffectShaderArgument stringWithQualifier:_qualifier], (unsigned long)location];
    }
}

+ (NSString *)stringWithQualifier:(CCEffectShaderArgumentQualifier)qualifier
{
    static NSArray *strings = nil;
    if (!strings)
    {
        strings = @[
                    @"buffer",
                    @"texture",
                    @"sampler",
                    @"stage_in",
                    @"vertex_id"
                    ];
    }
    
    return strings[qualifier];
}

@end


#pragma mark CCEffectShaderArgument

@implementation CCEffectShaderStructDeclaration

- (id)initWithName:(NSString *)name body:(NSString *)body
{
    if((self = [super init]))
    {
        _name = [name copy];
        _body = [body copy];
        
        _declaration = [NSString stringWithFormat:@"typedef struct %@\n{\n%@\n} %@", _name, _body, _name];
    }
    
    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    // CCEffectShaderStructDeclaration is immutable so no need to really copy.
    // Just return self.
    return self;
}


@end

