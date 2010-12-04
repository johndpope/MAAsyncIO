//
//  MAAsyncWriter.m
//  MAAsyncIO
//
//  Created by Michael Ash on 12/3/10.
//  Copyright 2010 Michael Ash. All rights reserved.
//

#import "MAAsyncWriter.h"

#import "MAFDSource.h"


@interface MAAsyncWriter ()

- (void)_write;

@end

@implementation MAAsyncWriter

- (id)initWithFileDescriptor: (int)fd
{
    if((self = [self init]))
    {
        _fdSource = [[MAFDSource alloc] initWithFileDescriptor: fd type: DISPATCH_SOURCE_TYPE_WRITE];
        _fd = fd;
        
        __block MAAsyncWriter *weakSelf = self;
        [_fdSource setEventCallback: ^{ [weakSelf _write]; }];
        
        _buffer = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_fdSource release];
    [_buffer release];
    [_errorHandler release];
    [_didWriteCallback release];
    [_eofCallback release];
    
    [super dealloc];
}

- (void)setErrorHandler: (void (^)(int err))block
{
    block = [block copy];
    [_errorHandler release];
    _errorHandler = block;
}

- (void)setTargetQueue: (dispatch_queue_t)queue
{
    [_fdSource setTargetQueue: queue];
}

- (void)setDidWriteCallback: (void (^)(void))block
{
    block = [block copy];
    [_didWriteCallback release];
    _didWriteCallback = block;
}

- (void)setEOFCallback: (void (^)(void))block
{
    block = [block copy];
    [_eofCallback release];
    _eofCallback = block;
}

- (void)writeData: (NSData *)data
{
    dispatch_async([_fdSource queue], ^{
        NSUInteger previousBufferLength = [_buffer length];
        [_buffer appendData: data];
        if(!previousBufferLength)
            [_fdSource resume];
    });
}

- (void)writeCString: (const char *)cstr
{
    [self writeData: [NSData dataWithBytes: cstr length: strlen(cstr)]];
}

- (NSUInteger)bufferSize
{
    return [_buffer length];
}

- (void)invalidate
{
    [_fdSource invalidate];
}

- (void)_write
{
    if([_buffer length])
    {
        ssize_t result = write(_fd, [_buffer bytes], [_buffer length]);
        NSUInteger didWrite = MAX(result, 0); // -1 (error) means wrote 0 bytes
        [_buffer replaceBytesInRange: NSMakeRange(0, didWrite) withBytes: NULL length: 0];
        
        if(result < 0)
        {
            if(errno != EAGAIN && errno != EINTR)
                if(_errorHandler)
                    _errorHandler(errno);
        }
        else if(result == 0)
        {
            if(_eofCallback)
                _eofCallback();
        }
        else
        {
            if(_didWriteCallback)
                _didWriteCallback();
        }
    }
    else
        [_fdSource suspend];
}

@end
