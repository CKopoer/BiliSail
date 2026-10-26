import hashlib
import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "ios_validation", Path(__file__).with_name("ios-package-validation.py"))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


def macho(platform=2, cpu=0x100000C):
    return (struct.pack("<8I", 0xFEEDFACF, cpu, 0, 6, 1, 24, 0, 0)
            + struct.pack("<6I", 0x32, 24, platform, 15 << 16, 18 << 16, 0))


def signature(info, bound=True):
    digest = hashlib.sha256(info).digest() if bound else b""
    cd = struct.pack(">9I4B", 0xFADE0C02, 40 + len(digest), 0x20001, 2,
                     40 + len(digest), 0, int(bound), 0, 0, 32, 2, 0, 12) + digest
    return struct.pack(">5I", 0xFADE0CC0, 20 + len(cd), 1, 0, 20) + cd


class IosValidationTests(unittest.TestCase):
    def test_ios_device_and_unsigned_binary(self):
        self.assertEqual(validation.inspect_macho(macho()), (None, False))

    def test_other_platforms_rejected_even_when_arm64(self):
        for platform in (1, 6, 7):
            with self.subTest(platform=platform), self.assertRaisesRegex(ValueError, "iPhoneOS"):
                validation.inspect_macho(macho(platform=platform))

    def test_wrong_architecture_rejected(self):
        with self.assertRaisesRegex(ValueError, "Non-arm64"):
            validation.inspect_macho(macho(cpu=0x1000007))

    def test_fat_device_slice(self):
        binary = macho()
        fat = struct.pack(">7I", 0xCAFEBABE, 1, 0x100000C, 0, 28, len(binary), 0) + binary
        self.assertEqual(validation.slices(fat), [binary])

    def test_truncated_load_command_rejected(self):
        with self.assertRaisesRegex(ValueError, "Truncated"):
            validation.inspect_macho(macho()[:-1])

    def test_info_hash_binding(self):
        info = plistlib.dumps({"CFBundleExecutable": "BiliMux"}, fmt=plistlib.FMT_BINARY)
        self.assertEqual(validation.verify_info_slot(signature(info), info), 1)

    def test_changed_plist_bytes_rejected(self):
        info = plistlib.dumps({"MinimumOSVersion": "15.0"})
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            validation.verify_info_slot(signature(info), info.replace(b"15.0", b"10.0"))

    def test_serialization_change_requires_resigning(self):
        value = {"CFBundleExecutable": "BiliMux"}
        xml, binary = plistlib.dumps(value), plistlib.dumps(value, fmt=plistlib.FMT_BINARY)
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            validation.verify_info_slot(signature(xml), binary)

    def test_unbound_plist_rejected(self):
        with self.assertRaisesRegex(ValueError, "not bound"):
            validation.verify_info_slot(signature(b"plist", bound=False), b"plist")

    def test_missing_signature_rejected(self):
        with self.assertRaisesRegex(ValueError, "Missing signature"):
            validation.verify_info_slot(None, b"plist")

    def test_package_processed_plist_and_all_nested_platforms(self):
        root = "Payload/Runner.app/"
        framework = root + "Frameworks/BiliMux.framework/"
        info = plistlib.loads((Path(__file__).parents[1] /
                              "packages/bili_mux/native/Info.ios.plist").read_bytes())
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "test.ipa"
            for fmt, platform, error in [(plistlib.FMT_BINARY, 2, None),
                                         (plistlib.FMT_XML, 2, "processed binary"),
                                         (plistlib.FMT_BINARY, 7, "iPhoneOS")]:
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr(root + "Info.plist", plistlib.dumps({
                        "CFBundleIdentifier": "dev.bilisail.bilisail", "MinimumOSVersion": "15.0"}))
                    archive.writestr(root + "Runner", macho())
                    archive.writestr(framework + "Info.plist", plistlib.dumps(info, fmt=fmt))
                    archive.writestr(framework + "BiliMux", macho())
                    archive.writestr(root + "Frameworks/Nested.dylib", macho(platform))
                if error:
                    with self.assertRaisesRegex(ValueError, error):
                        validation.validate_ipa(path)
                else:
                    validation.validate_ipa(path)


if __name__ == "__main__":
    unittest.main()
