//
//  HLS_Converter.m
//  cryptoBox (MilCryptor Secure Platform)
//
//  Created by Denys Borysiuk on 20.03.2018.
//  Copyright © 2016 ArchiSec Solutions, Ltd. All rights reserved.//
//

#import "HLS_Converter.h"

#include <libavformat/avformat.h>
#include <libavutil/opt.h>

@interface HLS_Converter () {
    dispatch_queue_t hlsQueue;
    
    AVFormatContext *ifmt_ctx;
    AVFormatContext *ofmt_ctx;
    int videoIndex;
    int audioIndex;
}

@end

@implementation HLS_Converter

- (instancetype)init {
    self = [super init];
    if (self) {
        hlsQueue = dispatch_queue_create("ffmpeg_hls_queue", NULL);
        ifmt_ctx = NULL;
        ofmt_ctx = NULL;
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (ifmt_ctx) {
        avformat_close_input(&ifmt_ctx);
        ifmt_ctx = 0;
    }
    if (ofmt_ctx) {
        if (ofmt_ctx->oformat && !(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
            avio_closep(&ofmt_ctx->pb);
        }
        avformat_close_input(&ofmt_ctx);
        ofmt_ctx = 0;
    }
}

- (NSDictionary*)openMovie:(NSString*)inPath {
    
    if ([self open_input_file:inPath.UTF8String]) {
        // Copy file metadata
        NSMutableDictionary *fileMeta = [NSMutableDictionary dictionary];
        AVDictionaryEntry *tag = NULL;
        while ((tag = av_dict_get(ifmt_ctx->metadata, "", tag, AV_DICT_IGNORE_SUFFIX))) {
            [fileMeta setObject:[NSString stringWithFormat:@"%s", tag->value] forKey:[NSString stringWithFormat:@"%s", tag->key]];
        }
        
        AVStream* stream = ifmt_ctx->streams[videoIndex];
        
        // Copy video metadata
        NSMutableDictionary *videoMeta = [NSMutableDictionary dictionary];
        while ((tag = av_dict_get(stream->metadata, "", tag, AV_DICT_IGNORE_SUFFIX))) {
            [videoMeta setObject:[NSString stringWithFormat:@"%s",tag->value] forKey:[NSString stringWithFormat:@"%s",tag->key]];
        }
        
        // Copy video matrix
        NSMutableData* matrix = [NSMutableData data];
        if (stream->side_data && stream->side_data->type == AV_PKT_DATA_DISPLAYMATRIX) {
            [matrix setData:[NSData dataWithBytes:stream->side_data->data length:stream->side_data->size]];
        }

        return @{@"fileMeta" : fileMeta, @"videoMeta" : videoMeta, @"matrix" : matrix};
    } else {
        return NULL;
    }
}

- (bool)openStream:(NSString*)inPath {
    return [self open_input_file:inPath.UTF8String];
}

- (bool)open_input_file:(const char *)filename {

    if (avformat_open_input(&ifmt_ctx, filename, NULL, NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open input file\n");
        return false;
    }

    if (avformat_find_stream_info(ifmt_ctx, NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find stream information\n");
        return false;
    }
    
    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *stream = ifmt_ctx->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoIndex = i;
        } else if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audioIndex = i;
        }
    }
    
//    av_dump_format(ifmt_ctx, 0, filename, 0);
    
    return true;
}

- (bool)create_output_file:(const char*)filename info:(NSDictionary*)info {
    
    int ret = avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, filename);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find output format\n");
        return false;
    }

    if (info) {
        NSDictionary* fileMeta = [info objectForKey:@"fileMeta"];
        for (NSString* key in [fileMeta allKeys]) {
            NSString* value = [fileMeta objectForKey:key];
            av_dict_set(&ofmt_ctx->metadata, key.UTF8String, value.UTF8String, 0);
        }
    }

    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        if (i == videoIndex || i == audioIndex) {
            AVStream *in_stream = ifmt_ctx->streams[i];
            AVCodecContext *in_ctx = in_stream->codec;
            
            AVCodec *encoder = avcodec_find_encoder(in_ctx->codec_id);
            AVStream *out_stream = avformat_new_stream(ofmt_ctx, encoder);
            if (!out_stream) {
                av_log(NULL, AV_LOG_ERROR, "Failed allocating output stream\n");
                return false;
            }
            AVCodecContext *out_ctx = out_stream->codec;
            
            out_ctx->codec_id = in_ctx->codec_id;
            out_ctx->codec_type = in_ctx->codec_type;

            if (in_ctx->codec_type == AVMEDIA_TYPE_VIDEO) {
                out_ctx->height = in_ctx->height;
                out_ctx->width = in_ctx->width;
                out_ctx->sample_aspect_ratio = in_ctx->sample_aspect_ratio;
                out_ctx->pix_fmt = in_ctx->pix_fmt;

                if (in_ctx->codec_id == AV_CODEC_ID_HEVC) {
                    out_ctx->codec_tag = MKTAG('h','v','c','1');
                }

                out_stream->time_base = out_ctx->time_base = (AVRational){1, 30};
                
                if (info) {
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
            } else {
                out_ctx->sample_rate = in_ctx->sample_rate;
                out_ctx->channel_layout = in_ctx->channel_layout;
                out_ctx->channels = av_get_channel_layout_nb_channels(out_ctx->channel_layout);
                out_ctx->sample_fmt = in_ctx->sample_fmt;
                out_stream->time_base = out_ctx->time_base = (AVRational){1, out_ctx->sample_rate};
            }

            const size_t extra_size_alloc = (in_ctx->extradata_size > 0) ? (in_ctx->extradata_size + AV_INPUT_BUFFER_PADDING_SIZE) : 0;
            if (extra_size_alloc)
            {
                out_ctx->extradata = (uint8_t*)av_mallocz(extra_size_alloc);
                memcpy( out_ctx->extradata, in_ctx->extradata, in_ctx->extradata_size);
            }
            out_ctx->extradata_size = in_ctx->extradata_size;
            
            ret = avcodec_parameters_from_context(out_stream->codecpar, out_ctx);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Error copy parameters from context\n");
                return false;
            }
            ret = avcodec_open2(out_ctx, encoder, NULL);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Cannot open encoder for stream #%u\n", i);
            }
        } else {
            continue;
        }
    }
    
    if (info == NULL) {
        av_opt_set_int(ofmt_ctx->priv_data, "hls_list_size", 0, 0);
    }
    
//    av_dump_format(ofmt_ctx, 0, filename, 1);
    
    if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, filename, AVIO_FLAG_WRITE);
        if (ret < 0) {
            av_log(NULL, AV_LOG_ERROR, "Could not open output file '%s'", filename);
            return false;
        }
    }
    
    ret = avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Error occurred when opening output file\n");
        return false;
    } else {
        return true;
    }
}

- (void)convertTo:(NSString*)outPath
             info:(NSDictionary*)info
    progressBlock:(HLS_ProgressBlock)progressBlock
  completionBlock:(HLS_CompletionBlock)completionBlock {
    
    dispatch_async(hlsQueue, ^{
        int ret = -1;
        int totalBytesRead = 0;

        if (![self create_output_file:outPath.UTF8String info:info]) {
            goto end;
        }

        // read all packets
        AVPacket packet = { .data = NULL, .size = 0 };
        while (1) {
            ret = av_read_frame(self->ifmt_ctx, &packet);
            if (ret < 0) {
                ret = 0; // finish stream
                break;
            } else {
                totalBytesRead += packet.size;
            }
            
            if (packet.stream_index != self->audioIndex && packet.stream_index != self->videoIndex) {
                av_packet_unref(&packet);
                continue;
            }
            
            // remux this frame without reencoding
            av_packet_rescale_ts(&packet,
                                 self->ifmt_ctx->streams[packet.stream_index]->time_base,
                                 self->ofmt_ctx->streams[packet.stream_index]->time_base);
            
            ret = av_interleaved_write_frame(self->ofmt_ctx, &packet);
            if (ret < 0) {
                av_packet_unref(&packet);
                break;
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
