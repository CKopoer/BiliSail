package dev.bilisail.bilisail

import androidx.media3.common.util.UnstableApi
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@UnstableApi
class Eac3SampleProbeTest {
    // Header-only fixtures. The encoded frame sizes include the zero-filled audio payload.
    private fun frame(size: Int, vararg header: Int) = ByteArray(size).also { frame ->
        header.forEachIndexed { index, value -> frame[index] = value.toByte() }
    }

    private val core = frame(2560, 0x0b, 0x77, 0, 0, 0x24, 0x40, 0x40)
    private val dependent = frame(4096, 0x0b, 0x77, 0x47, 0xff, 0x3a, 0x83,
        0xd1, 0xa0, 0x02, 0x08, 0x08, 0x80)
    private val ordinary = frame(768, 0x0b, 0x77, 0x01, 0x7f, 0x32, 0x80, 0)

    @Test fun findsJocAfterTheCoreAndAnEarlierDependentFrame() {
        val unmarked = dependent.clone().apply { this[8] = 0 }
        val second = dependent.clone().apply { this[2] = 0x4f }
        val sample = core + unmarked + second
        val probe = Eac3SampleProbe()
        // Split the final syncword across extractor reads, after the old 4096-byte limit.
        val split = core.size + unmarked.size + 1
        probe.append(sample, 0, split)
        probe.append(sample, split, sample.size - split)
        assertTrue(probe.containsJoc(sample.size, 0))
    }

    @Test fun respectsSampleBoundariesWhenTheExtractorReadsAhead() {
        val probe = Eac3SampleProbe()
        val first = core + dependent
        val data = first + ordinary + ByteArray(40000)
        probe.append(data, 0, data.size)
        assertTrue(probe.containsJoc(first.size, data.size - first.size))
        assertFalse(probe.containsJoc(ordinary.size, 40000))
        assertFalse(probe.containsJoc(core.size, data.size - core.size))
    }

    @Test fun ignoresPayloadSyncwordsAndTruncatedFrames() {
        val probe = Eac3SampleProbe()
        val fake = ordinary.clone().apply { dependent.copyInto(this, 100, 0, 12) }
        probe.append(fake, 0, fake.size)
        assertFalse(probe.containsJoc(fake.size, 0))
        probe.reset()
        probe.append(core, 0, core.size)
        probe.append(dependent, 0, dependent.size - 1)
        assertFalse(probe.containsJoc(core.size + dependent.size - 1, 0))
        probe.reset()
        probe.append(ordinary, 0, ordinary.size)
        assertFalse(probe.containsJoc(ordinary.size, 0))
    }

    @Test fun ignoresReservedBitstreamIdsAndStreamTypes() {
        val probe = Eac3SampleProbe()
        for (bad in listOf(
            dependent.clone().apply { this[5] = 0xff.toByte() },
            dependent.clone().apply { this[2] = 0xc7.toByte() },
        )) {
            probe.reset()
            probe.append(core, 0, core.size)
            probe.append(bad, 0, bad.size)
            assertFalse(probe.containsJoc(core.size + bad.size, 0))
        }
    }
}
