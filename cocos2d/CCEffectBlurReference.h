//
//  CCEffectBlurReference.h
//  cocos2d
//
//  Created by Thayer J Andrews on 4/9/15.
//
//

#import "CCEffect.h"


/**
 * CCEffectBlurReference performs a gaussian blur operation on the pixels of the attached node.
 * This is the simplest (and slowest) implementation and is used for comparison and testing of
 * the fast implementation.
 */

@interface CCEffectBlurReference : CCEffect


/// -----------------------------------------------------------------------
/// @name Blur Radius
/// -----------------------------------------------------------------------

/** The size of the blur. This value is in the range [0..n].
 *  @since v3.2 and later
 */
@property (nonatomic, assign) NSUInteger blurRadius;


/// -----------------------------------------------------------------------
/// @name Creating a Blur Effect
/// -----------------------------------------------------------------------

/**
 *  Creates a CCEffectBlurReference object with the specified parameters.
 *
 *  @param blurRadius the blur radius (in pixels) of the gaussian filter kernel
 *
 *  @return The CCEffectBlurReference object.
 *  @since v4.0 and later
 */
+(instancetype)effectWithBlurRadius:(NSUInteger)blurRadius;

/**
 *  Initializes a CCEffectBlurReference object with the following default parameters:
 *  blurRadius = 2
 *
 *  @return The CCEffectBlurReference object.
 *  @since v4.0 and later
 */
-(id)init;

/**
 *  Initializes a CCEffectBlurReference object with the specified parameters.
 *
 *  @param blurRadius the blur radius (in pixels) of the gaussian filter kernel
 *
 *  @return The CCEffectBlur object.
 *  @since v3.2 and later
 */
-(id)initWithPixelBlurRadius:(NSUInteger)blurRadius;

@end



