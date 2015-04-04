//
//  CCEffectFunction.m
//  cocos2d
//
//  Created by Thayer J Andrews on 3/5/15.
//
//

#import "CCEffectFunction.h"
#import "CCDeviceInfo.h"


#pragma mark CCEffectFunction

@implementation CCEffectFunction

-(id)initWithName:(NSString *)name body:(NSString*)body inputs:(NSArray*)inputs returnType:(NSString *)returnType
{
    NSAssert(name.length, @"");
    NSAssert(body.length, @"");
    NSAssert(returnType.length, @"");

    if((self = [super init]))
    {        
        _body = [body copy];
        _name = [name copy];
        _inputs = [inputs copy];
        _returnType = [returnType copy];
        
        NSString *inputString = @"void";
        if (_inputs.count)
        {
            NSMutableString *tmpString = [[NSMutableString alloc] init];
            for (CCEffectFunctionInput *input in _inputs)
            {
                [tmpString appendFormat:@"%@ %@", input.type, input.name];
                if (input != [_inputs lastObject])
                {
                    [tmpString appendString:@", "];
                }
            }
            inputString = tmpString;
        }
        
        _declaration = [NSString stringWithFormat:@"%@ %@(%@)", _returnType, _name, inputString];
        _definition = [NSString stringWithFormat:@"%@\n{\n%@\n}", _declaration, _body];
        
        return self;
    }
    
    return self;
}

+(instancetype)functionWithName:(NSString*)name body:(NSString*)body inputs:(NSArray*)inputs returnType:(NSString*)returnType
{
    return [[self alloc] initWithName:name body:body inputs:inputs returnType:returnType];
}

-(instancetype)copyWithZone:(NSZone *)zone
{
    // XXX CCEffectFunction is immutable. Just return self.
    CCEffectFunction *newFunction = [[CCEffectFunction allocWithZone:zone] initWithName:_name body:_body inputs:_inputs returnType:_returnType];
    return newFunction;
}

-(NSString*)callStringWithInputMappings:(NSDictionary*)inputMappings
{
    NSMutableString *callString = [[NSMutableString alloc] initWithFormat:@"%@(", _name];
    for (CCEffectFunctionInput *input in self.inputs)
    {
        NSString *mappedInput = inputMappings[input.name];
        [callString appendFormat:@"%@", mappedInput];
        if (input != [self.inputs lastObject])
        {
            [callString appendFormat:@", "];
        }
    }
    [callString appendString:@")"];
    
    return callString;
}

@end


#pragma mark CCEffectFunctionInput

@implementation CCEffectFunctionInput

-(id)initWithType:(NSString*)type name:(NSString*)name
{
    NSAssert(type.length, @"");
    NSAssert(name.length, @"");

    if((self = [super init]))
    {
        _type = [type copy];
        _name = [name copy];
        return self;
    }
    
    return self;
}

+(instancetype)inputWithType:(NSString*)type name:(NSString*)name
{
    return [[self alloc] initWithType:type name:name];
}

@end


#pragma mark CCEffectFunctionCall

@implementation CCEffectFunctionCall

-(id)initWithFunction:(CCEffectFunction *)function outputName:(NSString *)outputName inputs:(NSDictionary *)inputs
{
    NSAssert(function, @"");
    NSAssert(outputName.length, @"");
    
    if((self = [super init]))
    {
        _function = [function copy];
        _outputName = [outputName copy];
        _inputs = [inputs copy];
        
        // TODO Check that all of the functions inputs are represented in the inputs dictionary.
    }
    return self;
}

@end


#pragma mark CCEffectFunctionTemporary

@implementation CCEffectFunctionTemporary

-(id)initWithType:(NSString*)type name:(NSString*)name initializer:(CCEffectFunctionInitializer)initializer;
{
    NSAssert(type.length, @"");
    NSAssert(name.length, @"");
    NSAssert(initializer != CCEffectInitReserveOffset, @"");
    
    if((self = [super init]))
    {
        _type = [type copy];
        _name = [name copy];
        _initializer = initializer;
    }
    return self;
}

+(instancetype)temporaryWithType:(NSString*)type name:(NSString*)name initializer:(CCEffectFunctionInitializer)initializer
{
    if([CCDeviceInfo sharedDeviceInfo].graphicsAPI == CCGraphicsAPIMetal)
    {
        return [[CCEffectFunctionTemporaryMetal alloc] initWithType:type name:name initializer:initializer];
    }
    else
    {
        return [[CCEffectFunctionTemporaryGL alloc] initWithType:type name:name initializer:initializer];
    }
}

- (NSString *)declaration
{
    NSAssert(0, @"Subclasses must override this.");
    return nil;
}

-(BOOL)isValidForVertexShader
{
    switch (self.initializer)
    {
        case CCEffectInitVertexAttributes:
            return YES;
            break;
        default:
            return NO;
            break;
    }
}

-(BOOL)isValidForFragmentShader
{
    switch (self.initializer)
    {
        case CCEffectInitFragColor:
        case CCEffectInitMainTexture:
        case CCEffectInitPreviousPass:
        case CCEffectInitReserved0:
        case CCEffectInitReserved1:
        case CCEffectInitReserved2:
            return YES;
            break;
        default:
            return NO;
            break;
    }
}

+(CCEffectFunctionInitializer)promoteInitializer:(CCEffectFunctionInitializer)initializer
{
    if (initializer != CCEffectInitVertexAttributes)
    {
        initializer += CCEffectInitReserveOffset;
    }
    return initializer;
}


@end


#pragma mark CCEffectFunctionTemporaryGL

@interface CCEffectFunctionTemporaryGL ()

@property (nonatomic, strong) NSString *cachedDeclaration;

@end

@implementation CCEffectFunctionTemporaryGL

-(id)initWithType:(NSString*)type name:(NSString*)name initializer:(CCEffectFunctionInitializer)initializer;
{
    if((self = [super initWithType:type name:name initializer:initializer]))
    {
        _cachedDeclaration = nil;
    }
 
    return self;
}

- (NSString *)declaration
{
    if (!_cachedDeclaration)
    {
        switch (self.initializer)
        {
            case CCEffectInitVertexAttributes:
                _cachedDeclaration = [NSString stringWithFormat:@"%@ %@ = cc_Position", self.type, self.name];
                break;
            case CCEffectInitFragColor:
                _cachedDeclaration = [NSString stringWithFormat:@"%@ %@ = cc_FragColor", self.type, self.name];
                break;
            case CCEffectInitMainTexture:
                _cachedDeclaration = [NSString stringWithFormat:@"vec2 compare_%@ = cc_FragTexCoord1Extents - abs(cc_FragTexCoord1 - cc_FragTexCoord1Center);\n"
                                      @"%@ %@ = cc_FragColor * texture2D(cc_MainTexture, cc_FragTexCoord1) * step(0.0, min(compare_%@.x, compare_%@.y))", self.name, self.type, self.name, self.name, self.name];
                break;
            case CCEffectInitPreviousPass:
                _cachedDeclaration = [NSString stringWithFormat:@"vec2 compare_%@ = cc_FragTexCoord1Extents - abs(cc_FragTexCoord1 - cc_FragTexCoord1Center);\n"
                                      @"%@ %@ = cc_FragColor * texture2D(cc_PreviousPassTexture, cc_FragTexCoord1) * step(0.0, min(compare_%@.x, compare_%@.y))", self.name, self.type, self.name, self.name, self.name];
                break;
            case CCEffectInitReserved0:
                _cachedDeclaration = [NSString stringWithFormat:@"%@ %@ = vec4(1)", self.type, self.name];
                break;
            case CCEffectInitReserved1:
                _cachedDeclaration = [NSString stringWithFormat:@"vec2 compare_%@ = cc_FragTexCoord1Extents - abs(cc_FragTexCoord1 - cc_FragTexCoord1Center);\n"
                                      @"%@ %@ = texture2D(cc_MainTexture, cc_FragTexCoord1) * step(0.0, min(compare_%@.x, compare_%@.y))", self.name, self.type, self.name, self.name, self.name];
                break;
            case CCEffectInitReserved2:
                _cachedDeclaration = [NSString stringWithFormat:@"vec2 compare_%@ = cc_FragTexCoord1Extents - abs(cc_FragTexCoord1 - cc_FragTexCoord1Center);\n"
                                      @"%@ %@ = texture2D(cc_PreviousPassTexture, cc_FragTexCoord1) * step(0.0, min(compare_%@.x, compare_%@.y))", self.name, self.type, self.name, self.name, self.name];
                break;
            case CCEffectInitReserveOffset:
                NSAssert(0, @"");
                break;
        }
    }
    return _cachedDeclaration;
}

@end


#pragma mark CCEffectFunctionTemporaryMetal

@interface CCEffectFunctionTemporaryMetal ()

@property (nonatomic, strong) NSString *cachedDeclaration;

@end

@implementation CCEffectFunctionTemporaryMetal

-(id)initWithType:(NSString*)type name:(NSString*)name initializer:(CCEffectFunctionInitializer)initializer;
{
    if((self = [super initWithType:type name:name initializer:initializer]))
    {
        _cachedDeclaration = nil;
    }
    
    return self;
}

- (NSString *)declaration
{
    if (!_cachedDeclaration)
    {
        switch (self.initializer)
        {
            case CCEffectInitVertexAttributes:
                _cachedDeclaration = [NSString stringWithFormat:@"%@ %@;\n"
                                      @"%@.position = cc_VertexAttributes[cc_VertexId].position;\n"
                                      @"%@.texCoord1 = cc_VertexAttributes[cc_VertexId].texCoord1;\n"
                                      @"%@.texCoord2 = cc_VertexAttributes[cc_VertexId].texCoord2;\n"
                                      @"%@.color = saturate(half4(cc_VertexAttributes[cc_VertexId].color))", self.type, self.name, self.name, self.name, self.name, self.name];
                break;
            case CCEffectInitFragColor:
                _cachedDeclaration = [NSString stringWithFormat:@"%@ %@ = cc_FragIn.color", self.type, self.name];
                break;
            case CCEffectInitMainTexture:
                _cachedDeclaration = [NSString stringWithFormat:@"float2 compare_%@ = cc_FragTexCoordDimensions->texCoord1Extents - abs(cc_FragIn.texCoord1 - cc_FragTexCoordDimensions->texCoord1Center);\n"
                                      @"%@ %@ = cc_FragIn.color * cc_MainTexture.sample(cc_MainTextureSampler, cc_FragIn.texCoord1) * step(0.0, min(compare_%@.x, compare_%@.y))", self.name, self.type, self.name, self.name, self.name];
                break;
            case CCEffectInitPreviousPass:
                _cachedDeclaration = [NSString stringWithFormat:@"float2 compare_%@ = cc_FragTexCoordDimensions->texCoord1Extents - abs(cc_FragIn.texCoord1 - cc_FragTexCoordDimensions->texCoord1Center);\n"
                                      @"%@ %@ = cc_FragIn.color * cc_PreviousPassTexture.sample(cc_PreviousPassTextureSampler, cc_FragIn.texCoord1) * step(0.0, min(compare_%@.x, compare_%@.y))", self.name, self.type, self.name, self.name, self.name];
                break;
            case CCEffectInitReserved0:
                _cachedDeclaration = [NSString stringWithFormat:@"%@ %@ = half4(1)", self.type, self.name];
                break;
            case CCEffectInitReserved1:
                _cachedDeclaration = [NSString stringWithFormat:@"float2 compare_%@ = cc_FragTexCoordDimensions->texCoord1Extents - abs(cc_FragIn.texCoord1 - cc_FragTexCoordDimensions->texCoord1Center);\n"
                                      @"%@ %@ = cc_MainTexture.sample(cc_MainTextureSampler, cc_FragIn.texCoord1) * step(0.0, min(compare_%@.x, compare_%@.y))", self.name, self.type, self.name, self.name, self.name];
                break;
            case CCEffectInitReserved2:
                _cachedDeclaration = [NSString stringWithFormat:@"float2 compare_%@ = cc_FragTexCoordDimensions->texCoord1Extents - abs(cc_FragIn.texCoord1 - cc_FragTexCoordDimensions->texCoord1Center);\n"
                                      @"%@ %@ = cc_PreviousPassTexture.sample(cc_PreviousPassTextureSampler, cc_FragIn.texCoord1) * step(0.0, min(compare_%@.x, compare_%@.y))", self.name, self.type, self.name, self.name, self.name];
                break;
            case CCEffectInitReserveOffset:
                NSAssert(0, @"");
                break;
        }
    }
    return _cachedDeclaration;
}

@end
