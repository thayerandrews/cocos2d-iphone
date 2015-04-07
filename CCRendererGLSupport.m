/*
 * Cocos2D-SpriteBuilder: http://cocos2d.spritebuilder.com
 *
 * Copyright (c) 2014 Cocos2D Authors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "CCRenderer_Private.h"
#import "CCTexture_Private.h"
#import "CCSetup_Private.h"
#import "CCShader_Private.h"

#import "CCRenderDispatch.h"


@implementation CCTextureGL

- (void) dealloc
{
	CCLOGINFO(@"cocos2d: deallocing %@", self);
	
	GLuint name = _name;
	if(name){
		CCRenderDispatch(YES, ^{
			CCGL_DEBUG_PUSH_GROUP_MARKER("CCTexture: Dealloc");
			glDeleteTextures(1, &name);
			CCGL_DEBUG_POP_GROUP_MARKER();
		});
	}
    
    [super dealloc];
}

static GLenum
GLTypeForCCTextureType(CCTextureType type)
{
    switch(type){
        case CCTextureType2D: return GL_TEXTURE_2D;
        case CCTextureTypeCubemap: return GL_TEXTURE_CUBE_MAP;
    }
}

-(GLenum)glType
{
    return GLTypeForCCTextureType(self.type);
}

-(void)_setupTexture:(CCTextureType)type rendertexture:(BOOL)rendertexture sizeInPixels:(CGSize)sizeInPixels mipmapped:(BOOL)mipmapped;
{
    glGenTextures(1, &_name);
}

-(void)_setupSampler:(CCTextureType)type
    minFilter:(CCTextureFilter)minFilter magFilter:(CCTextureFilter)magFilter mipFilter:(CCTextureFilter)mipFilter
    addressX:(CCTextureAddressMode)addressX addressY:(CCTextureAddressMode)addressY
{
    GLenum target = GLTypeForCCTextureType(type);
    glBindTexture(target, _name);
    
    // Set up texture filtering mode.
    static const GLenum FILTERS[3][3] = {
        {GL_LINEAR, GL_LINEAR, GL_LINEAR}, // Invalid enum, fall back to linear.
        {GL_NEAREST, GL_NEAREST_MIPMAP_NEAREST, GL_NEAREST_MIPMAP_LINEAR}, // nearest
        {GL_LINEAR, GL_LINEAR_MIPMAP_NEAREST, GL_LINEAR_MIPMAP_LINEAR}, // linear
    };

    glTexParameteri(target, GL_TEXTURE_MIN_FILTER, FILTERS[minFilter][mipFilter]);
    glTexParameteri(target, GL_TEXTURE_MAG_FILTER, FILTERS[magFilter][CCTextureFilterMipmapNone]);
    
    // Set up texture wrap mode.
    static const GLenum ADDRESSING[] = {
        GL_CLAMP_TO_EDGE,
        GL_REPEAT,
        GL_MIRRORED_REPEAT,
    };
    
    glTexParameteri(target, GL_TEXTURE_WRAP_S, ADDRESSING[addressX]);
    glTexParameteri(target, GL_TEXTURE_WRAP_T, ADDRESSING[addressY]);
}

-(void)_uploadTexture2D:(CGSize)sizeInPixels miplevel:(NSUInteger)miplevel pixelData:(const void *)pixelData;
{
    glTexImage2D(GL_TEXTURE_2D, (GLint)miplevel, GL_RGBA, (GLsizei)sizeInPixels.width, (GLsizei)sizeInPixels.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixelData);
}

-(void)_uploadTextureCubeFace:(NSUInteger)face sizeInPixels:(CGSize)sizeInPixels miplevel:(NSUInteger)miplevel pixelData:(const void *)pixelData
{
    glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + (GLenum)face, (GLint)miplevel, GL_RGBA, (GLsizei)sizeInPixels.width, (GLsizei)sizeInPixels.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixelData);
}

-(void)_generateMipmaps:(CCTextureType)type
{
    // TODO should this check for full NPOT texture support here?
    glGenerateMipmap(GLTypeForCCTextureType(type));
}

@end


static const CCGraphicsBufferType CCGraphicsBufferGLTypes[] = {
	GL_ARRAY_BUFFER,
	GL_ELEMENT_ARRAY_BUFFER,
};


@interface CCGraphicsBufferGLBasic : CCGraphicsBuffer @end
@implementation CCGraphicsBufferGLBasic {
	@public
	GLuint _buffer;
	GLenum _type;
}

-(instancetype)initWithCapacity:(NSUInteger)capacity elementSize:(size_t)elementSize type:(CCGraphicsBufferType)type;
{
	if((self = [super initWithCapacity:capacity elementSize:elementSize type:type])){
		glGenBuffers(1, &_buffer);
		_type = CCGraphicsBufferGLTypes[type];
		
		[self setup];
	}
	
	return self;
}

-(void)setup
{
	_ptr = calloc(_capacity, _elementSize);
}

-(void)destroy
{
	free(_ptr);
	_ptr = NULL;
	
	GLuint buffer = _buffer;
	CCRenderDispatch(YES, ^{glDeleteBuffers(1, &buffer);});
}

-(void)resize:(size_t)newCapacity;
{
	_ptr = realloc(_ptr, newCapacity*_elementSize);
	_capacity = newCapacity;
}

-(void)prepare;
{
	_count = 0;
}

-(void)commit;
{
	GLenum type = (GLenum)_type;
	glBindBuffer(type, _buffer);
	glBufferData(type, (GLsizei)(_count*_elementSize), _ptr, GL_STREAM_DRAW);
	glBindBuffer(type, 0);
}

@end


#if __CC_PLATFORM_IOS

@interface CCGraphicsBufferGLUnsynchronized : CCGraphicsBufferGLBasic @end
@implementation CCGraphicsBufferGLUnsynchronized {
	GLvoid *(*_mapBufferRange)(GLenum target, GLintptr offset, GLsizeiptr length, GLbitfield access);
	GLvoid (*_flushMappedBufferRange)(GLenum target, GLintptr offset, GLsizeiptr length);
	GLboolean (*_unmapBuffer)(GLenum target);
}

#define BUFFER_ACCESS_WRITE (GL_MAP_WRITE_BIT_EXT | GL_MAP_UNSYNCHRONIZED_BIT_EXT | GL_MAP_INVALIDATE_BUFFER_BIT_EXT | GL_MAP_FLUSH_EXPLICIT_BIT_EXT)
#define BUFFER_ACCESS_READ (GL_MAP_READ_BIT_EXT)

-(instancetype)initWithCapacity:(NSUInteger)capacity elementSize:(size_t)elementSize type:(CCGraphicsBufferType)type
{
	if((self = [super initWithCapacity:capacity elementSize:elementSize type:type])){
		// TODO Does Android look up GL functions by name like Windows/Linux?
		_mapBufferRange = glMapBufferRangeEXT;
		_flushMappedBufferRange = glFlushMappedBufferRangeEXT;
		_unmapBuffer = glUnmapBufferOES;
	}
	
	return self;
}

-(void)setup
{
	glBindBuffer(_type, _buffer);
	glBufferData(_type, _capacity*_elementSize, NULL, GL_STREAM_DRAW);
	glBindBuffer(_type, 0);
	CC_CHECK_GL_ERROR_DEBUG();
}

-(void)destroy
{
	GLuint buffer = _buffer;
	CCRenderDispatch(YES, ^{glDeleteBuffers(1, &buffer);});
}

-(void)resize:(size_t)newCapacity
{
	// This is a little tricky.
	// Need to resize the existing GL buffer object without creating a new name.
	
	// Make the buffer readable.
	glBindBuffer(_type, _buffer);
	GLsizei oldLength = (GLsizei)(_count*_elementSize);
	_flushMappedBufferRange(_type, 0, oldLength);
	_unmapBuffer(_type);
	void *oldBufferPtr = _mapBufferRange(_type, 0, oldLength, BUFFER_ACCESS_READ);
	
	// Copy the old contents into a temp buffer.
	GLsizei newLength = (GLsizei)(newCapacity*_elementSize);
	void *tempBufferPtr = malloc(newLength);
	memcpy(tempBufferPtr, oldBufferPtr, oldLength);
	
	// Copy that into a new GL buffer.
	_unmapBuffer(_type);
	glBufferData(_type, newLength, tempBufferPtr, GL_STREAM_DRAW);
	void *newBufferPtr = _mapBufferRange(_type, 0, newLength, BUFFER_ACCESS_WRITE);
	
	// Cleanup.
	free(tempBufferPtr);
	glBindBuffer(_type, 0);
	CC_CHECK_GL_ERROR_DEBUG();
	
	// Update values.
	_ptr = newBufferPtr;
	_capacity = newCapacity;
}

-(void)prepare
{
	_count = 0;
	
	GLenum target = (GLenum)_type;
	glBindBuffer(_type, _buffer);
	_ptr = _mapBufferRange(target, 0, (GLsizei)(_capacity*_elementSize), BUFFER_ACCESS_WRITE);
	glBindBuffer(target, 0);
	CC_CHECK_GL_ERROR_DEBUG();
}

-(void)commit
{
	glBindBuffer(_type, _buffer);
	_flushMappedBufferRange(_type, 0, (GLsizei)(_count*_elementSize));
	_unmapBuffer(_type);
	glBindBuffer(_type, 0);
	CC_CHECK_GL_ERROR_DEBUG();
	
	_ptr = NULL;
}

@end

#endif


@interface CCGraphicsBufferBindingsGL : CCGraphicsBufferBindings @end
@implementation CCGraphicsBufferBindingsGL {
	GLuint _vao;
	
	// Cache the currently bound page to avoid switching it if possible
	NSUInteger _currentPage;
}

static inline void
BindVertexPage(CCGraphicsBufferBindingsGL *self, NSUInteger page)
{
	if(page != self->_currentPage){
		size_t pageOffset = page*(1<<16)*sizeof(CCVertex);
		
		glBindBuffer(GL_ARRAY_BUFFER, ((CCGraphicsBufferGLBasic *)self->_vertexBuffer)->_buffer);
		glVertexAttribPointer(CCShaderAttributePosition, 4, GL_FLOAT, GL_FALSE, sizeof(CCVertex), (void *)(pageOffset + offsetof(CCVertex, position)));
		glVertexAttribPointer(CCShaderAttributeTexCoord1, 2, GL_FLOAT, GL_FALSE, sizeof(CCVertex), (void *)(pageOffset + offsetof(CCVertex, texCoord1)));
		glVertexAttribPointer(CCShaderAttributeTexCoord2, 2, GL_FLOAT, GL_FALSE, sizeof(CCVertex), (void *)(pageOffset + offsetof(CCVertex, texCoord2)));
		glVertexAttribPointer(CCShaderAttributeColor, 4, GL_FLOAT, GL_FALSE, sizeof(CCVertex), (void *)(pageOffset + offsetof(CCVertex, color)));
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		
		self->_currentPage = page;
	}
}

-(instancetype)init
{
	if((self = [super init])){
		CCRenderDispatch(NO, ^{
			const NSUInteger CCRENDERER_INITIAL_VERTEX_CAPACITY = 16*1024;
			_vertexBuffer = [[CCGraphicsBufferClass alloc] initWithCapacity:CCRENDERER_INITIAL_VERTEX_CAPACITY elementSize:sizeof(CCVertex) type:CCGraphicsBufferTypeVertex];
			[_vertexBuffer prepare];
			
			_indexBuffer = [[CCGraphicsBufferClass alloc] initWithCapacity:CCRENDERER_INITIAL_VERTEX_CAPACITY*1.5 elementSize:sizeof(uint16_t) type:CCGraphicsBufferTypeIndex];
			[_indexBuffer prepare];
			
			CCGL_DEBUG_PUSH_GROUP_MARKER("CCGraphicsBufferBindingsGL: Creating VAO");
			
			glGenVertexArrays(1, &_vao);
			glBindVertexArray(_vao);

			glEnableVertexAttribArray(CCShaderAttributePosition);
			glEnableVertexAttribArray(CCShaderAttributeTexCoord1);
			glEnableVertexAttribArray(CCShaderAttributeTexCoord2);
			glEnableVertexAttribArray(CCShaderAttributeColor);
			
			_currentPage = NSUIntegerMax; // Start with an invalid value.
			BindVertexPage(self, 0);
			
			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ((CCGraphicsBufferGLBasic *)_indexBuffer)->_buffer);

			glBindVertexArray(0);
			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
			
			CCGL_DEBUG_POP_GROUP_MARKER();
		});
	}
	
	return self;
}

-(void)dealloc
{
	GLuint vao = _vao;
	CCRenderDispatch(YES, ^{glDeleteVertexArrays(1, &vao);});
    
    [super dealloc];
}

-(void)bind:(BOOL)bind vertexPage:(NSUInteger)vertexPage
{
	CCGL_DEBUG_INSERT_EVENT_MARKER("CCGraphicsBufferBindingsGL: Bind VAO");
	
	if(bind){
		glBindVertexArray(_vao);
		BindVertexPage(self, vertexPage);
	} else {
		glBindVertexArray(0);
	}
}

@end


@interface CCFrameBufferObjectGL : CCFrameBufferObject @end
@implementation CCFrameBufferObjectGL {
	GLuint _fbo;
	GLuint _depthRenderBuffer;
	GLuint _stencilRenderBuffer;
}

-(instancetype)initWithTexture:(CCTexture *)texture depthStencilFormat:(GLuint)depthStencilFormat
{
	if((self = [super initWithTexture:texture depthStencilFormat:depthStencilFormat])){
		CCRenderDispatch(NO, ^{
			CCGL_DEBUG_PUSH_GROUP_MARKER("CCRenderTexture: Create");
			
			// generate FBO
			glGenFramebuffers(1, &_fbo);
			glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
			
			// associate texture with FBO
			glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, [(CCTextureGL *)texture name], 0);
			
			GLuint width = (GLuint)texture.sizeInPixels.width;
			GLuint height = (GLuint)texture.sizeInPixels.height;

#if __CC_PLATFORM_ANDROID
			
			// Some android devices *only* support combined depth buffers (like all iOS devices), some android devices do not
			// support combined depth buffers, thus we have to create a seperate stencil buffer
			if(_depthStencilFormat)
			{
					//create and attach depth buffer
			
					if(![[CCDeviceInfo sharedDeviceInfo] supportsPackedDepthStencil])
					{
							glGenRenderbuffers(1, &_depthRenderBuffer);
							glBindRenderbuffer(GL_RENDERBUFFER, _depthRenderBuffer);
							glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width, height); //GL_DEPTH_COMPONENT24_OES
							glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthRenderBuffer);

							// if depth format is the one with stencil part, bind same render buffer as stencil attachment
							if(_depthStencilFormat == GL_DEPTH24_STENCIL8)
							{
									glGenRenderbuffers(1, &_stencilRenderBuffer);
									glBindRenderbuffer(GL_RENDERBUFFER, _stencilRenderBuffer);
									glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, width, height);
									glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _stencilRenderBuffer);
							}
					}
					else
					{
							glGenRenderbuffers(1, &_depthRenderBuffer);
							glBindRenderbuffer(GL_RENDERBUFFER, _depthRenderBuffer);
							glRenderbufferStorage(GL_RENDERBUFFER, _depthStencilFormat, width, height);
							glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthRenderBuffer);
							
							// if depth format is the one with stencil part, bind same render buffer as stencil attachment
							if(_depthStencilFormat == GL_DEPTH24_STENCIL8){
									glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _depthRenderBuffer);
							}
					}
			}
			
#else
			
			if(depthStencilFormat){
				//create and attach depth buffer
				glGenRenderbuffers(1, &_depthRenderBuffer);
				glBindRenderbuffer(GL_RENDERBUFFER, _depthRenderBuffer);
				glRenderbufferStorage(GL_RENDERBUFFER, depthStencilFormat, width, height);
				glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthRenderBuffer);

				// if depth format is the one with stencil part, bind same render buffer as stencil attachment
				if(depthStencilFormat == GL_DEPTH24_STENCIL8){
					glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _depthRenderBuffer);
				}
			}
			
#endif
		
			// check if it worked (probably worth doing :) )
			NSAssert( glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, @"Could not attach texture to framebuffer");
						
			CCGL_DEBUG_POP_GROUP_MARKER();
			CC_CHECK_GL_ERROR_DEBUG();
		});
	}
	return self;
}

-(void)dealloc
{
	GLuint fbo = _fbo;
	GLuint depthRenderBuffer = _depthRenderBuffer;
	GLuint stencilRenderBuffer = _stencilRenderBuffer;
	
	CCRenderDispatch(YES, ^{
		glDeleteFramebuffers(1, &fbo);
		
		if(depthRenderBuffer){
			glDeleteRenderbuffers(1, &depthRenderBuffer);
		}
		
		if(depthRenderBuffer){
			glDeleteRenderbuffers(1, &stencilRenderBuffer);
		}
	});
    
    [super dealloc];
}

-(void)bindWithClear:(GLbitfield)mask color:(GLKVector4)color4 depth:(GLclampf)depth stencil:(GLint)stencil
{
	glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
	
	CGSize size = self.sizeInPixels;
	glViewport(0, 0, size.width, size.height);
	
	if(mask & GL_COLOR_BUFFER_BIT) glClearColor(color4.r, color4.g, color4.b, color4.a);
	if(mask & GL_DEPTH_BUFFER_BIT) glClearDepth(depth);
	if(mask & GL_STENCIL_BUFFER_BIT) glClearStencil(stencil);
	if(mask) glClear(mask);
	
	// Enabled depth testing if there is a depth buffer.
	if(_depthStencilFormat){
		glEnable(GL_DEPTH_TEST);
		glDepthFunc(GL_LEQUAL);
	}
}

-(void)syncWithView:(CC_VIEW<CCView> *)view;
{
	[super syncWithView:view];
	_fbo = [view fbo];
}

@end

@interface CCRenderStateGL : CCRenderState @end
@implementation CCRenderStateGL

static void
CCRenderStateGLTransition(CCRenderStateGL *self, CCRenderer *renderer, CCRenderStateGL *previous)
{
	CCGL_DEBUG_PUSH_GROUP_MARKER("CCRenderStateGL: Transition");
	
	// Set the blending state.
	if(previous ==  nil || self->_blendMode != previous->_blendMode){
		CCGL_DEBUG_INSERT_EVENT_MARKER("Blending mode");
		
		NSDictionary *blendOptions = self->_blendMode->_options;
		if(blendOptions == CCBLEND_DISABLED_OPTIONS){
			glDisable(GL_BLEND);
		} else {
			glEnable(GL_BLEND);
			
			glBlendFuncSeparate(
				[blendOptions[CCBlendFuncSrcColor] unsignedIntValue],
				[blendOptions[CCBlendFuncDstColor] unsignedIntValue],
				[blendOptions[CCBlendFuncSrcAlpha] unsignedIntValue],
				[blendOptions[CCBlendFuncDstAlpha] unsignedIntValue]
			);
			
			glBlendEquationSeparate(
				[blendOptions[CCBlendEquationColor] unsignedIntValue],
				[blendOptions[CCBlendEquationAlpha] unsignedIntValue]
			);
		}
	}
	
	// Bind the shader.
	BOOL bindShader = (previous == nil || self->_shader != previous->_shader);
	if(bindShader){
		CCGL_DEBUG_INSERT_EVENT_MARKER("Shader");
		
		glUseProgram(self->_shader->_program);
	}
	
	// Set the shader's uniform state.
	if(bindShader || self->_shaderUniforms != previous->_shaderUniforms){
		CCGL_DEBUG_INSERT_EVENT_MARKER("Uniforms");
		
		NSDictionary *globalShaderUniforms = renderer->_globalShaderUniforms;
		NSDictionary *setters = self->_shader->_uniformSetters;
		for(NSString *uniformName in setters){
			CCUniformSetter setter = setters[uniformName];
			setter(renderer, self->_shaderUniforms, globalShaderUniforms);
		}
	}
	
	CCGL_DEBUG_POP_GROUP_MARKER();
	CC_CHECK_GL_ERROR_DEBUG();
}

-(void)transitionRenderer:(CCRenderer *)renderer FromState:(CCRenderStateGL *)previous
{
	CCRenderStateGLTransition(self, renderer, previous);
}

@end

@interface CCRenderCommandDrawGL : CCRenderCommandDraw @end
@implementation CCRenderCommandDrawGL

static const CCRenderCommandDrawMode GLDrawModes[] = {
	GL_TRIANGLES,
	GL_LINES,
};

-(void)invokeOnRenderer:(CCRenderer *)renderer
{
	CCGL_DEBUG_PUSH_GROUP_MARKER("CCRendererCommandDraw: Invoke");
	
	CCRendererBindBuffers(renderer, YES, _vertexPage);
	CCRenderStateGLTransition((CCRenderStateGL *)_renderState, renderer, (CCRenderStateGL *)renderer->_renderState);
	renderer->_renderState = _renderState;
	
	glDrawElements(GLDrawModes[_mode], (GLsizei)_count, GL_UNSIGNED_SHORT, (GLvoid *)(_firstIndex*sizeof(GLushort)));
    
	CCGL_DEBUG_POP_GROUP_MARKER();
}

@end
