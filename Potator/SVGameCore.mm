/*
 Copyright (c) 2009, OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the OpenEmu Team nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SVGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>
#import <OpenGL/gl.h>
#import "OESVSystemResponderClient.h"


#import "supervision.h"

@interface SVGameCore () <OESVSystemResponderClient>
{
    uint16_t *videoBuffer;
    int16_t pad[OESVButtonCount];
    NSString *romName;
    double sampleRate;

    BOOL paused;

    uint8_t *romBuffer;
    size_t   romBufferSize;

    COLOR_SCHEME displayMode;
}

@end


#define SCREEN_HEIGHT 160
#define SCREEN_WIDTH  160
#define SCREEN_AREA SCREEN_HEIGHT*SCREEN_WIDTH
@implementation SVGameCore

static __weak SVGameCore *_current;

- (id)init
{
    self = [super init];
    if(self)
    {
        videoBuffer = (uint16_t*)malloc(SCREEN_AREA*2);
        paused = YES;

        romBuffer = NULL;
        romBufferSize = 0;

        displayMode = COLOUR_SCHEME_DEFAULT;
    }

    _current = self;

    return self;
}

#pragma mark - Input
- (oneway void)didPushSVButton:(OESVButton)button;
{
    pad[button] = 1;
}

- (oneway void)didReleaseSVButton:(OESVButton)button;
{
    pad[button] = 0;
}

- (void)changeDisplayMode
{
    displayMode = (COLOR_SCHEME)((displayMode+1) % COLOUR_SCHEME_COUNT);
    supervision_set_colour_scheme(displayMode);
}

/*
 extern void supervision_init(void);
 extern void supervision_reset(void);
 extern void supervision_reset_handler(void);
 extern void supervision_done(void);
 extern void supervision_exec(int16 *backbuffer, BOOL bRender);
 extern void supervision_exec2(int16 *backbuffer, BOOL bRender);
 extern void supervision_exec3(int16 *backbuffer, BOOL bRender);
 extern void supervision_exec_fast(int16 *backbuffer, BOOL bRender);
 extern BOOL supervision_load(uint8 *rom, uint32 romSize);
 extern BOOL supervision_update_input(void);
 ---    extern void supervision_set_colour_scheme(COLOR_SCHEME ws_colourScheme);
 extern M6502	*supervision_get6502regs(void);
 extern void supervision_turnSound(BOOL bOn);

 extern int	sv_loadState(char *statepath, int id);
 extern int	sv_saveState(char *statepath, int id);
 */
#pragma mark - Old Stuff

static void audio_callback(int16_t left, int16_t right)
{
    GET_CURRENT_AND_RETURN();

    [[current ringBufferAtIndex:0] write:&left maxLength:2];
    [[current ringBufferAtIndex:0] write:&right maxLength:2];
}

static size_t audio_batch_callback(const int16_t *data, size_t frames)
{
    GET_CURRENT_AND_RETURN(frames);

    [[current ringBufferAtIndex:0] write:data maxLength:frames << 2];
    return frames;
}

#pragma mark Exectuion
- (void)executeFrame
{
    [self executeFrameSkippingFrame:NO];
}

- (void)executeFrameSkippingFrame: (BOOL) skip
{
    static NSUInteger frameCount = 0;

    supervision_update_input();
    supervision_exec((int16*)videoBuffer,1);
    controls_reset();




    /*
     if(frameCount > 500){
     int x, y;
     uint16_t *pSrc;

     NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(160, 160)];
     [image lockFocus];
     pSrc = videoBuffer;
     for ( y = 0; y < 160; y++ )
     {
     for ( x = 0; x < 160; x++ )
     {
     printf("%04x", *pSrc);
     pSrc++;
     continue;

     uint8_t   red = ((*pSrc)&0x7C00)>>10;
     uint8_t green = ((*pSrc)&0x03E0)>>5;
     uint8_t  blue = (*pSrc)&0x001F;
     //                printf("%02x %02x %02x\n", red, green, blue);
     NSColor *c = [NSColor colorWithDeviceRed:red/(float)0x1F green:green/(float)0x1F blue:blue/(float)0x1F alpha:1.0];
     [c setFill];
     NSRectFill(NSMakeRect(x, y, 1, 1));

     pSrc++;
     }
     }
     [image unlockFocus];

     NSString *file = [[NSString stringWithFormat:@"~/Desktop/Frames/Frame %ld.tiff", frameCount] stringByExpandingTildeInPath];
     [[image TIFFRepresentation] writeToFile:file atomically:YES];
     }
     */
    frameCount++;
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    // Zero out pad data
    memset(pad, 0, sizeof(int16_t) * OESVButtonCount);

    romName = [path copy];
    if(romBuffer != NULL)
    {
        NSLog(@"WARNING: Releasing current rom buffer!");
        free(romBuffer);
        romBuffer = NULL;
        romBufferSize = 0;
    }

    //load cart, read bytes, get length
    NSData* dataObj = [NSData dataWithContentsOfFile:[romName stringByStandardizingPath] options:0 error:error];
    if(dataObj == nil)
        return false;

    romBufferSize = [dataObj length];
    romBuffer = (uint8_t*)malloc(romBufferSize);
    [dataObj getBytes:romBuffer length:romBufferSize];

    supervision_init();
    return supervision_load(romBuffer, (uint32_t)romBufferSize);
}

#pragma mark Video
- (const void *)videoBuffer
{
    return videoBuffer;
}

- (OEIntRect)screenRect
{
    return OEIntRectMake(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(SCREEN_WIDTH, SCREEN_HEIGHT);
}

- (OEIntSize)aspectSize
{
    return OEIntSizeMake(1, 1);
}

- (void)resetEmulation
{
    supervision_reset();
}

- (void)stopEmulation
{
    NSString *path = romName;
    NSString *extensionlessFilename = [[path lastPathComponent] stringByDeletingPathExtension];

    NSString *batterySavesDirectory = [self batterySavesDirectoryPath];

    if([batterySavesDirectory length] != 0)
    {
        [[NSFileManager defaultManager] createDirectoryAtPath:batterySavesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    supervision_done();

    [super stopEmulation];
}

- (void)dealloc
{
    free(videoBuffer);
}

- (GLenum)pixelFormat
{
    return GL_BGRA;
}

- (GLenum)pixelType
{
    //   return GL_UNSIGNED_SHORT_5_5_5_1;
    return GL_UNSIGNED_SHORT_1_5_5_5_REV;
}

- (GLenum)internalPixelFormat
{
    return GL_RGB5;
}

- (double)audioSampleRate
{
    return sampleRate ? sampleRate : 48000;
}

- (NSTimeInterval)frameInterval
{
    return frameInterval ? frameInterval : 2097152./35112.; // 59.7
}

- (NSUInteger)channelCount
{
    return 2;
}

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
}

#pragma mark - Cheats

NSMutableDictionary *cheatList = [[NSMutableDictionary alloc] init];

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
}

@end
