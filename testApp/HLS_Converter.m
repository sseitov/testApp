//
//  HLS_Converter.m
//  cryptoBox (MilCryptor Secure Platform)
//
//  Created by Denys Borysiuk on 20.03.2018.
//  Copyright © 2016 ArchiSec Solutions, Ltd. All rights reserved.//
//

#import "HLS_Converter.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavfilter/avfiltergraph.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>

@interface HLS_Converter () {
    dispatch_queue_t hlsQueue;
    dispatch_queue_t callbackQueue;

    AVCodecContext* videoContext;
    AVCodecContext* audioContext;
    
    AVFormatContext *ifmt_ctx;
    AVFormatContext *ofmt_ctx;
    AVBitStreamFilterContext *filter;
}

@end

@implementation HLS_Converter

- (instancetype)init {
    self = [super init];
    if (self) {
        av_register_all();
        avcodec_register_all();
        avformat_network_init();
        
        hlsQueue = dispatch_queue_create("ffmpeg_hls_queue", NULL);
        ifmt_ctx = NULL;
        ofmt_ctx = NULL;
        filter = NULL;
        videoContext = NULL;
        audioContext = NULL;
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (filter) {
        av_bitstream_filter_close(filter);
        filter = NULL;
    }
    
    if (videoContext) {
        avcodec_free_context(&videoContext);
        videoContext = NULL;
    }
    if (audioContext) {
        avcodec_free_context(&audioContext);
        audioContext = NULL;
    }
    if (ifmt_ctx) {
        avformat_close_input(&ifmt_ctx);
        ifmt_ctx = NULL;
    }

    if (ofmt_ctx) {
        if (ofmt_ctx && !(ofmt_ctx->oformat->flags & AVFMT_NOFILE))
            avio_closep(&ofmt_ctx->pb);
        avformat_free_context(ofmt_ctx);
        ofmt_ctx = NULL;
    }
}

- (int)applyBitstreamFilter:(AVBitStreamFilterContext*)bitstreamFilterContext packet:(AVPacket*)packet outputCodecContext:(AVCodecContext*)outputCodecContext {
    
    AVPacket newPacket = *packet;
    int a = av_bitstream_filter_filter(bitstreamFilterContext, outputCodecContext, NULL,
                                       &newPacket.data, &newPacket.size,
                                       packet->data, packet->size,
                                       packet->flags & AV_PKT_FLAG_KEY);
    
    if(a == 0 && newPacket.data != packet->data) {
        uint8_t *t = av_malloc(newPacket.size + AV_INPUT_BUFFER_PADDING_SIZE);
        if(t) {
            memcpy(t, newPacket.data, newPacket.size);
            memset(t + newPacket.size, 0, AV_INPUT_BUFFER_PADDING_SIZE);
            newPacket.data = t;
            newPacket.buf = NULL;
            newPacket.size = newPacket.size + AV_INPUT_BUFFER_PADDING_SIZE;
            a = 1;
        } else {
            a = AVERROR(ENOMEM);
        }
    }
    
    if (a > 0) {
        av_packet_unref(packet);
        newPacket.buf = av_buffer_create(newPacket.data, newPacket.size,
                                         av_buffer_default_free, NULL, 0);
        if (!newPacket.buf) {
            NSLog(@"new packet buffer couldnt be allocated");
        }
        
    } else if (a < 0) {
        NSLog(@"FFmpeg Error: Failed to open bitstream filter %s for stream %d with codec %s", bitstreamFilterContext->filter->name, packet->stream_index,
              outputCodecContext->codec ? outputCodecContext->codec->name : "copy");
    }
    
    *packet = newPacket;
    return a;
}

- (BOOL)updateContext {
    int ret;

    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *stream = ifmt_ctx->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO || stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            AVCodec *dec = avcodec_find_decoder(stream->codecpar->codec_id);
            AVCodecContext *codec_ctx;
            if (!dec) {
                av_log(NULL, AV_LOG_ERROR, "Failed to find decoder for stream #%u\n", i);
                return NO;
            }
            codec_ctx = avcodec_alloc_context3(dec);
            if (!codec_ctx) {
                av_log(NULL, AV_LOG_ERROR, "Failed to allocate the decoder context for stream #%u\n", i);
                return NO;
            }
            
            ret = avcodec_parameters_to_context(codec_ctx, stream->codecpar);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Failed to copy decoder parameters to input decoder context for stream #%u\n", i);
                return NO;
            }
            // Reencode video & audio and remux subtitles etc.
            
            if (codec_ctx->codec_type == AVMEDIA_TYPE_VIDEO)
                codec_ctx->framerate = av_guess_frame_rate(ifmt_ctx, stream, NULL);
            
            // Open decoder
            ret = avcodec_open2(codec_ctx, dec, NULL);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Failed to open decoder for stream #%u\n", i);
                return NO;
            }
            if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                videoContext = codec_ctx;
            } else {
                audioContext = codec_ctx;
            }
        }
    }
    return YES;
}

- (NSDictionary*)openMovie:(NSString*)inPath {
    
    int ret;
    NSMutableDictionary *fileMeta = [NSMutableDictionary dictionary];
    NSMutableDictionary *videoMeta = [NSMutableDictionary dictionary];
    NSMutableData* matrix = [NSMutableData data];

    ifmt_ctx = avformat_alloc_context();
    if ((ret = avformat_open_input(&ifmt_ctx, inPath.UTF8String, NULL, NULL)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open input file\n");
        return NULL;
    }
    
    if ((ret = avformat_find_stream_info(ifmt_ctx, NULL)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find stream information\n");
        return NULL;
    }
    
    if (![self updateContext]) {
        return NULL;
    }
    
    // Copy file metadata
    
    AVDictionaryEntry *tag = NULL;
    while ((tag = av_dict_get(ifmt_ctx->metadata, "", tag, AV_DICT_IGNORE_SUFFIX))) {
        NSLog(@"%s - %s\n", tag->value, tag->key);
        [fileMeta setObject:[NSString stringWithFormat:@"%s", tag->value] forKey:[NSString stringWithFormat:@"%s", tag->key]];
    }
    
    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream* stream = ifmt_ctx->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            if (stream->codecpar->codec_id == AV_CODEC_ID_HEVC) {
                filter = av_bitstream_filter_init("hevc_mp4toannexb");
            } else {
                filter = av_bitstream_filter_init("h264_mp4toannexb");
            }
            
            // Copy video metadata
            NSMutableDictionary *videoMeta = [NSMutableDictionary dictionary];
            while ((tag = av_dict_get(stream->metadata, "", tag, AV_DICT_IGNORE_SUFFIX))) {
                NSLog(@"%s - %s\n", tag->value, tag->key);
                [videoMeta setObject:[NSString stringWithFormat:@"%s",tag->value] forKey:[NSString stringWithFormat:@"%s",tag->key]];
            }
            
            // Copy video matrix
            if (stream->side_data && stream->side_data->type == AV_PKT_DATA_DISPLAYMATRIX) {
                [matrix setData:[NSData dataWithBytes:stream->side_data->data length:stream->side_data->size]];
            }
        }
        
    }
    
    return @{@"fileMeta" : fileMeta, @"videoMeta" : videoMeta, @"matrix" : matrix};
}

- (BOOL)openStream:(NSString*)inPath {
    int ret;
    
    ifmt_ctx = avformat_alloc_context();
    if ((ret = avformat_open_input(&ifmt_ctx, inPath.UTF8String, NULL, NULL)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open input file\n");
        return NO;
    }

    if ((ret = avformat_find_stream_info(ifmt_ctx, NULL)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find stream information\n");
        return NO;
    }
  
    if (![self updateContext]) {
        return NULL;
    }

    filter = av_bitstream_filter_init("aac_adtstoasc");
    return YES;
}

- (BOOL)create_output_file:(const char*)filename info:(NSDictionary*)info {
    
    int ret = avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, filename);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find output format\n");
        return NO;
    }

    if (info) {
        NSDictionary* fileMeta = [info objectForKey:@"fileMeta"];
        for (NSString* key in [fileMeta allKeys]) {
            NSString* value = [fileMeta objectForKey:key];
            av_dict_set(&ofmt_ctx->metadata, key.UTF8String, value.UTF8String, 0);
        }
    }
    
    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream* in_stream = ifmt_ctx->streams[i];
        if (in_stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO || in_stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            AVStream *out_stream = avformat_new_stream(ofmt_ctx, NULL);
            AVCodecParameters *in_codecpar = in_stream->codecpar;
            if (!out_stream) {
                av_log(NULL, AV_LOG_ERROR, "Failed allocating output stream\n");
                return NO;
            }
            ret = avcodec_parameters_copy(out_stream->codecpar, in_codecpar);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Failed to copy codec parameters\n");
                return NO;
            }
            if (in_codecpar->codec_id == AV_CODEC_ID_HEVC) {
                out_stream->codecpar->codec_tag = MKTAG('h','v','c','1');
            } else {
                out_stream->codecpar->codec_tag = 0;
            }
            
            if (info && in_codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                NSDictionary * videoMeta = [info objectForKey:@"videoMeta"];
                for (NSString* key in [videoMeta allKeys]) {
                    NSString* value = [videoMeta objectForKey:key];
                    av_dict_set(&out_stream->metadata, key.UTF8String, value.UTF8String, 0);
                }
                
                NSData* matrix = [info objectForKey:@"matrix"];
                if (matrix.length > 0) {
                    out_stream->side_data = malloc(sizeof(AVPacketSideData*));
                    out_stream->nb_side_data = 1;
                    AVPacketSideData* side_data = &out_stream->side_data[0];
                    side_data->type = AV_PKT_DATA_DISPLAYMATRIX;
                    side_data->size = (int)matrix.length;
                    side_data->data = malloc(side_data->size);
                    memcpy(side_data->data, matrix.bytes, side_data->size);
                }
            }
        }
    }
    
    if (info == NULL) {
        av_opt_set_int(ofmt_ctx->priv_data, "hls_list_size", 0, 0);
    }
    
    av_dump_format(ofmt_ctx, 0, filename, 1);
    
    if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, filename, AVIO_FLAG_WRITE);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Could not open output file '%s'", filename);
            return NO;
        }
    }
    
    ret = avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Error occurred when opening output file %d\n", ret);
        return NO;
    } else {
        return YES;
    }
}

- (void)convertTo:(NSString*)outPath info:(NSDictionary*)info progressBlock:(HLS_ProgressBlock)progressBlock completionBlock:(HLS_CompletionBlock)completionBlock {
    
    dispatch_async(hlsQueue, ^{
        unsigned int stream_index;
        int videoIndex = -1;
        int audioIndex = -1;
        int ret = -1;
        
        for (int i = 0; i < self->ifmt_ctx->nb_streams; i++) {
            AVStream *stream = self->ifmt_ctx->streams[i];
            if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                videoIndex = i;
            } else if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
                audioIndex = i;
            }
        }
        
        if (![self create_output_file:outPath.UTF8String info:info]) {
            goto end;
        }

        // read all packets
        self.cancelOperation = NO;
        int totalBytesRead = 0;
        AVPacket packet = { .data = NULL, .size = 0 };
        while (1) {
            ret = av_read_frame(self->ifmt_ctx, &packet);
            if (ret < 0 || self.cancelOperation) {
                if (self.cancelOperation) {
                    ret = -1;
                } else {
                    ret = 0;
                }
                break;
            } else {
                totalBytesRead += packet.size;
            }
            
            stream_index = packet.stream_index;
            if (stream_index != audioIndex && stream_index != videoIndex) {
                av_packet_unref(&packet);
                continue;
            }
            
            // remux this frame without reencoding
            av_packet_rescale_ts(&packet,
                                 self->ifmt_ctx->streams[stream_index]->time_base,
                                 self->ofmt_ctx->streams[stream_index]->time_base);
            
            if (info == NULL) {
                if (stream_index == videoIndex) {
                    ret = [self applyBitstreamFilter:self->filter packet:&packet outputCodecContext:self->videoContext];
                }
            } else {
                if (stream_index == audioIndex) {
                    ret = [self applyBitstreamFilter:self->filter packet:&packet outputCodecContext:self->audioContext];
                }
            }
            if (ret < 0) {
                av_packet_unref(&packet);
                goto end;
            }
            
            ret = av_interleaved_write_frame(self->ofmt_ctx, &packet);
            if (ret < 0) {
                av_packet_unref(&packet);
                goto end;
            }
            
            if (progressBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    progressBlock(totalBytesRead);
                });
            }
            
            av_packet_unref(&packet);
        }

        av_write_trailer(self->ofmt_ctx);
        
    end:
        [self close];
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(ret == 0);
        });
    });
}

@end
