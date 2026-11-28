typedef PlaybackCacheLimits = ({int forwardMiB, int backwardMiB});

const defaultForwardCacheMiB = 16;
const defaultVodBackwardCacheMiB = 8;
const defaultVodCacheLimits = (
  forwardMiB: defaultForwardCacheMiB,
  backwardMiB: defaultVodBackwardCacheMiB,
);
const defaultLiveCacheLimits = (
  forwardMiB: defaultForwardCacheMiB,
  backwardMiB: 0,
);
const maximumPlaybackCacheMiB = 128;

bool isValidPlaybackCacheLimits(PlaybackCacheLimits limits) =>
    limits.forwardMiB >= 1 &&
    limits.forwardMiB <= maximumPlaybackCacheMiB &&
    limits.backwardMiB >= 0 &&
    limits.backwardMiB <= maximumPlaybackCacheMiB;
