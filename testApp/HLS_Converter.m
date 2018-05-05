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
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>

@interface HLS_Converter () {
    dispatch_queue_t hlsQueue;
    dispatch_queue_t callbackQueue;
    
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
        av_register_all();
        avcodec_register_all();
        avformat_network_init();
        
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
        for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
            avcodec_close(ifmt_ctx->streams[i]->codec);
        }
        avformat_close_input(&ifmt_ctx);
        ifmt_ctx = 0;
    }
    if (ofmt_ctx) {
        for (int i = 0; i < ofmt_ctx->nb_streams; i++) {
            avcodec_close(ofmt_ctx->streams[i]->codec);
        }
        if (ofmt_ctx->oformat && !(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
            avio_closep(&ofmt_ctx->pb);
        }
        avformat_close_input(&ofmt_ctx);
        ofmt_ctx = 0;
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

- (NSDictionary*)openMovie:(NSString*)inPath {
    if ([self open_input_file:inPath.UTF8String] == 0) {
        // Copy file metadata
        NSMutableDictionary *fileMeta = [NSMutableDictionary dictionary];
        AVDictionaryEntry *tag = NULL;
        while ((tag = av_dict_get(ifmt_ctx->metadata, "", tag, AV_DICT_IGNORE_SUFFIX))) {
            NSLog(@"%s - %s\n", tag->value, tag->key);
            [fileMeta setObject:[NSString stringWithFormat:@"%s", tag->value] forKey:[NSString stringWithFormat:@"%s", tag->key]];
        }
        
        AVStream* stream = ifmt_ctx->streams[videoIndex];
        
        // Copy video metadata
        NSMutableDictionary *videoMeta = [NSMutableDictionary dictionary];
        while ((tag = av_dict_get(stream->metadata, "", tag, AV_DICT_IGNORE_SUFFIX))) {
            NSLog(@"%s - %s\n", tag->value, tag->key);
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

- (BOOL)openStream:(NSString*)inPath {
    return ([self open_input_file:inPath.UTF8String] == 0);
}

- (int)open_input_file:(const char *)filename {
    
    int ret;
    unsigned int i;

    ifmt_ctx = NULL;
    if ((ret = avformat_open_input(&ifmt_ctx, filename, NULL, NULL)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open input file\n");
        return ret;
    }

    if ((ret = avformat_find_stream_info(ifmt_ctx, NULL)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find stream information\n");
        return ret;
    }
    
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *stream;
        AVCodecContext *codec_ctx;
        stream = ifmt_ctx->streams[i];
        codec_ctx = stream->codec;
        if (codec_ctx->codec_type == AVMEDIA_TYPE_VIDEO || codec_ctx->codec_type == AVMEDIA_TYPE_AUDIO) {
            // Open decoder
            AVCodec *codec = avcodec_find_decoder(codec_ctx->codec_id);
            ret = avcodec_open2(codec_ctx, codec, NULL);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Failed to open decoder for stream #%u\n", i);
                return ret;
            }
            if (codec_ctx->codec_type == AVMEDIA_TYPE_VIDEO) {
                videoIndex = i;
            } else {
                audioIndex = i;
            }
        }
    }
    
//    av_dump_format(ifmt_ctx, 0, filename, 0);
    
    return 0;
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
        
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVCodecContext *in_ctx = in_stream->codec;
        
        if (in_ctx->codec_type == AVMEDIA_TYPE_VIDEO || in_ctx->codec_type == AVMEDIA_TYPE_AUDIO) {
            const char *codec_name = avcodec_get_name(in_ctx->codec_id);
            AVCodec *encoder = avcodec_find_encoder(in_ctx->codec_id);
            
            if (!encoder) {
                av_log(NULL, AV_LOG_FATAL, "Necessary encoder %s not found\n", codec_name);
            }
            
            AVStream *out_stream = avformat_new_stream(ofmt_ctx, encoder);
            if (!out_stream) {
                av_log(NULL, AV_LOG_ERROR, "Failed allocating output stream\n");
                return NO;
            }
            AVCodecContext *out_ctx = out_stream->codec;
            
            out_ctx->codec_id = in_ctx->codec_id;
            out_ctx->codec_type = in_ctx->codec_type;
            out_stream->time_base = out_ctx->time_base = (AVRational){1, out_ctx->sample_rate};

            if (in_ctx->codec_type == AVMEDIA_TYPE_VIDEO) {
                out_ctx->height = in_ctx->height;
                out_ctx->width = in_ctx->width;
                out_ctx->sample_aspect_ratio = in_ctx->sample_aspect_ratio;
                out_ctx->pix_fmt = in_ctx->pix_fmt;

                if (in_ctx->codec_id == AV_CODEC_ID_HEVC) {
                    out_ctx->codec_tag = MKTAG('h','v','c','1');
                }

                out_stream->time_base = out_ctx->time_base = (AVRational){1, 30};
                
                const size_t extra_size_alloc = (in_ctx->extradata_size > 0) ? (in_ctx->extradata_size + AV_INPUT_BUFFER_PADDING_SIZE) : 0;
                if (extra_size_alloc)
                {
                    out_ctx->extradata = (uint8_t*)av_mallocz(extra_size_alloc);
                    memcpy( out_ctx->extradata, in_ctx->extradata, in_ctx->extradata_size);
                }
                out_ctx->extradata_size = in_ctx->extradata_size;
                
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
            }
            ret = avcodec_open2(out_ctx, encoder, NULL);
            if (ret < 0) {
                av_log(NULL, AV_LOG_ERROR, "Cannot open encoder for stream #%u\n", i);
            }
        } else if (in_ctx->codec_type == AVMEDIA_TYPE_UNKNOWN) {
            av_log(NULL, AV_LOG_FATAL, "Elementary stream #%d is of unknown type, cannot proceed\n", i);
            return NO;
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
            return NO;
        }
    }
    
    ret = avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) {
        av_log(NULL, AV_LOG_ERROR, "Error occurred when opening output file\n");
        return NO;
    } else {
        return YES;
    }
}

- (void)convertTo:(NSString*)outPath info:(NSDictionary*)info progressBlock:(HLS_ProgressBlock)progressBlock completionBlock:(HLS_CompletionBlock)completionBlock {
    
    dispatch_async(hlsQueue, ^{
        unsigned int stream_index;
        AVBitStreamFilterContext *filter = 0;
        int ret = -1;
        
        if (![self create_output_file:outPath.UTF8String info:info]) {
            goto end;
        }
        
        if (info == NULL) {
            if (self->ifmt_ctx->streams[self->videoIndex]->codec->codec_id == AV_CODEC_ID_HEVC) {
                filter = av_bitstream_filter_init("hevc_mp4toannexb");
            } else {
                filter = av_bitstream_filter_init("h264_mp4toannexb");
            }
        } else {
            filter = av_bitstream_filter_init("aac_adtstoasc");
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
            if (stream_index != self->audioIndex && stream_index != self->videoIndex) {
                av_packet_unref(&packet);
                continue;
            }
            
            // remux this frame without reencoding
            av_packet_rescale_ts(&packet,
                                 self->ifmt_ctx->streams[stream_index]->time_base,
                                 self->ofmt_ctx->streams[stream_index]->time_base);
            
            if (info == NULL) {
                if (stream_index == self->videoIndex) {
                    ret = [self applyBitstreamFilter:filter packet:&packet outputCodecContext:self->ofmt_ctx->streams[stream_index]->codec];
                }
            } else {
//                if (stream_index == self->audioIndex) {
//                    ret = [self applyBitstreamFilter:filter packet:&packet outputCodecContext:self->ofmt_ctx->streams[stream_index]->codec];
//                }
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
        if (filter) {
            av_bitstream_filter_close(filter);
        }
        
        if (self->ofmt_ctx) {
            for (int i = 0; i < self->ofmt_ctx->nb_streams; i++) {
                avcodec_close(self->ofmt_ctx->streams[i]->codec);
            }
            if (!(self->ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
                avio_closep(&self->ofmt_ctx->pb);
                if (ret < 0) {
                    av_log(NULL, AV_LOG_ERROR, "Could not close output file");
                }
            }
            avformat_free_context(self->ofmt_ctx);
            self->ofmt_ctx = 0;
        }
        [self close];
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(ret == 0);
        });
    });
}

@end
