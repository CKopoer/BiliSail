"""Check both channels of the macOS system output against the offline stereo mix."""
from pathlib import Path
import sys

import numpy as np
from scipy.io import wavfile


def compare(reference, capture):
    from scipy.signal import correlate, correlation_lags

    rate, pcm = wavfile.read(reference)
    output_rate, output = wavfile.read(capture)
    if rate != output_rate or pcm.shape[1] != 2 or output.shape[1] != 2:
        raise ValueError("Expected two stereo recordings with matching sample rates")
    source, recorded = pcm.astype(float), output.astype(float)
    if max(abs(recorded.ravel())) < 100:
        raise ValueError("Silent loopback")
    # Align once for both channels. A late or repeated packet must stay visible.
    mono = source.mean(axis=1)
    captured = recorded.mean(axis=1)
    peak = np.argmax(correlate(captured, mono, method="fft"))
    offset = int(correlation_lags(len(captured), len(mono))[peak])
    width = rate // 10
    for channel in range(2):
        minimum_energy = max(abs(source[:, channel])) * 0.015 * np.sqrt(width)
        scores = []
        for start in range(0, len(source) - width + 1, width):
            expected = source[start:start + width, channel]
            energy = np.linalg.norm(expected)
            if energy < minimum_energy:
                continue
            index = start + offset
            if index < 0 or index + width > len(recorded):
                scores.append(0.)
                continue
            actual = recorded[index:index + width, channel]
            scores.append(np.dot(expected, actual) / max(1., energy * np.linalg.norm(actual)))
        matches = sum(score >= 0.95 for score in scores)
        if len(scores) < 30:
            raise ValueError("Insufficient audible reference audio")
        print(f"Channel {channel + 1}: {matches}/{len(scores)} windows match, "
              f"minimum correlation {min(scores):.4f}", flush=True)
        if matches < 0.95 * len(scores):
            raise ValueError("Discontinuous or missing system audio")


def record(path):
    import sounddevice as sd

    rate = 48000
    recording = sd.rec(13 * rate, samplerate=rate, channels=2, dtype="int16",
                       device="BlackHole 2ch", latency="high")
    Path(path + ".ready").touch()
    status = sd.wait()
    if status:
        raise RuntimeError(f"Loopback recording lost samples: {status}")
    wavfile.write(path, rate, recording)


if __name__ == "__main__":
    if sys.argv[1] == "--record":
        record(sys.argv[2])
    else:
        compare(*sys.argv[1:])
