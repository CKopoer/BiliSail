"""Check the iOS pod against the audio_service version resolved by Flutter."""

from pathlib import Path
import tempfile
import unittest

from media_kit_sources import package_source
from prepare_ios_audio_service import IMPLEMENTATION, prepare


class IOSAudioServicePodTest(unittest.TestCase):
    def test_repeated_pod_install_uses_the_patched_copy(self):
        source = package_source("audio_service")
        original = (source / IMPLEMENTATION).read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            link = repo / "ios/.symlinks/plugins/audio_service"
            link.parent.mkdir(parents=True)
            link.symlink_to(source, target_is_directory=True)
            for _ in range(2):
                destination = prepare(repo, source)
                self.assertEqual(link.resolve(), destination)
                self.assertTrue((link / "darwin/audio_service.podspec").is_file())
                self.assertIn(b"publishBackgroundNowPlayingInfo", (link / IMPLEMENTATION).read_bytes())
                self.assertEqual((source / IMPLEMENTATION).read_bytes(), original)
