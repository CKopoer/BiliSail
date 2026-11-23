"""Check the native bundles and compile input used by the Windows runner."""

import json
from pathlib import Path
import tempfile
import unittest

from media_kit_sources import package_source, stage


class WindowsVideoAssetsTests(unittest.TestCase):
    def test_both_architectures_use_the_reviewed_render_api_build(self):
        catalog = json.loads((package_source("media_kit") / "hook/native_bundles.json").read_text())
        archives = {
            "windows_x64": ("7z", "bb6ce9e53c083002fad640011632aef96167cb1d4fffcfe4ed79acbc153bb497"),
            "windows_arm64": ("zip", "0a9067375c6517b93549fa421a4ab16b301a93b4d91e653117e8b053e1490d83"),
        }
        for target, (archive_format, digest) in archives.items():
            bundle = catalog["bundles"][target]
            self.assertEqual(bundle["format"], archive_format)
            self.assertEqual(bundle["sha256"], digest)
            self.assertEqual(bundle["library"], "libmpv-2.dll")
            self.assertIn("/Predidit/libmpv-win32-video-cmake/releases/download/202611230430/", bundle["url"])

    def test_patched_renderer_keeps_upstream_d3d11_and_owns_retired_textures(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = Path(directory) / "plugin"
            source = package_source("media_kit_video")
            stage(source, dest, ["windows"])
            output = (dest / "windows/video_output.cc").read_text(encoding="utf-8")
            self.assertIn("MPV_RENDER_API_TYPE_D3D11", output)
            self.assertIn("std::atomic_load(&output->visible)", output)
            self.assertIn("mpv_render_context_free(render_context_)", output)
            manager = (dest / "windows/video_output_manager.cc").read_text(encoding="utf-8")
            self.assertNotIn(".detach()", manager)
            self.assertIn("management_tasks_.Post", manager)
            mailbox = (dest / "windows/mailbox_swap_chain.cc").read_text(encoding="utf-8")
            self.assertIn("has_completed_frame_", mailbox)
            self.assertIn("context4_->Signal", mailbox)
