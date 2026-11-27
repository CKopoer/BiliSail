// Runs only in the macOS loopback regression. The application never links this code.
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#include <mpv/client.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <stdatomic.h>

static BOOL (*systemReady)(id, SEL);
static void (*systemEnqueue)(id, SEL, CMSampleBufferRef);

static _Atomic double queuedEnd;
static _Atomic bool discontinuity;

static void enqueue(AVSampleBufferAudioRenderer *renderer, SEL sel, CMSampleBufferRef sample)
{
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    CMTime end = CMTimeAdd(pts, CMSampleBufferGetDuration(sample));
    double start = CMTimeGetSeconds(pts);
    double previous = queuedEnd;
    if (previous && fabs(start - previous) > 1.0 / 48000) {
        fprintf(stderr, "Discontinuous JOC timestamps: %.6f to %.6f seconds\n", previous, start);
        discontinuity = true;
    }
    queuedEnd = CMTimeGetSeconds(end);
    systemEnqueue(renderer, sel, sample);
}

static BOOL ready(AVSampleBufferAudioRenderer *renderer, SEL sel)
{
    double now = CMTimeGetSeconds(CMTimebaseGetTime(renderer.timebase));
    // Allow normal startup, then model a route which signals readiness late.
    if (now > 1 && queuedEnd - now >= 0.020) return NO;
    return systemReady(renderer, sel);
}

int main(int argc, char **argv)
{
    if (argc != 3) return 2;
    bool pressure = strcmp(argv[2], "pressure") == 0;
    if (!pressure && strcmp(argv[2], "joc") != 0) return 2;
    Class cls = [AVSampleBufferAudioRenderer class];
    Method method = class_getInstanceMethod(cls, @selector(enqueueSampleBuffer:));
    systemEnqueue = (void *)method_setImplementation(method, (IMP)enqueue);
    if (pressure) {
        method = class_getInstanceMethod(cls, @selector(isReadyForMoreMediaData));
        systemReady = (void *)method_setImplementation(method, (IMP)ready);
    }

    mpv_handle *player = mpv_create();
    if (!player || mpv_set_option_string(player, "vid", "no") < 0 ||
        mpv_set_option_string(player, "audio-spdif", "apple-joc") < 0 ||
        mpv_initialize(player) < 0) return 2;
    mpv_request_log_messages(player, "warn");
    const char *load[] = {"loadfile", argv[1], NULL};
    if (mpv_command(player, load) < 0) return 2;
    bool sawJoc = false, otherOutput = false, ended = false;
    time_t deadline = time(NULL) + 20;
    while (time(NULL) < deadline && !ended) {
        mpv_event *event = mpv_wait_event(player, 0.1);
        if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
            mpv_event_log_message *log = event->data;
            fprintf(stderr, "[%s] %s", log->prefix, log->text);
        }
        if (event->event_id == MPV_EVENT_END_FILE) {
            ended = ((mpv_event_end_file *)event->data)->reason == MPV_END_FILE_REASON_EOF;
            break;
        }
        char *ao = mpv_get_property_string(player, "current-ao");
        if (ao && strcmp(ao, "apple-joc") == 0) sawJoc = true;
        if (ao && *ao && strcmp(ao, "apple-joc") != 0) otherOutput = true;
        mpv_free(ao);
    }
    mpv_terminate_destroy(player);
    fprintf(stderr, "%s: reachedEOF=%d apple-joc=%d otherOutput=%d discontinuity=%d\n",
            argv[2], ended, sawJoc, otherOutput, (int)discontinuity);
    return ended && sawJoc && !otherOutput && !discontinuity ? 0 : 1;
}
