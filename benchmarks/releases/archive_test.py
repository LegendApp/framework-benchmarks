import io
import os
import pathlib
import tarfile
import tempfile
import unittest
import sys
sys.dont_write_bytecode = True
from archive import create, extract


class ArchiveTests(unittest.TestCase):
    def test_roundtrip_modes_symlinks_and_hardlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            bundle = root / "Example.app"
            bundle.mkdir()
            binary = bundle / "binary"
            binary.write_bytes(b"executable bytes")
            binary.chmod(0o755)
            (bundle / "alias").symlink_to("binary")
            os.link(binary, bundle / "hardlink")
            create(bundle, root / "app.tar.gz")
            extract(root / "app.tar.gz", root / "out", bundle.name)
            result = root / "out" / bundle.name
            self.assertEqual((result / "binary").read_bytes(), binary.read_bytes())
            self.assertEqual((result / "binary").stat().st_mode & 0o777, 0o755)
            self.assertEqual(os.readlink(result / "alias"), "binary")
            self.assertEqual((result / "hardlink").read_bytes(), binary.read_bytes())

    def reject(self, entries):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            with tarfile.open(root / "bad.tar.gz", "w:gz") as archive:
                for name, target in entries:
                    info = tarfile.TarInfo(name)
                    if target is not None:
                        info.type = tarfile.SYMTYPE
                        info.linkname = target
                    archive.addfile(info, io.BytesIO(b""))
            with self.assertRaises((ValueError, RuntimeError)):
                extract(root / "bad.tar.gz", root / "out", "Example.app")
            self.assertFalse((root / "escaped").exists())

    def test_parent_escape(self):
        self.reject([("Example.app/../../escaped", None)])

    def test_absolute_escape(self):
        self.reject([("/tmp/escaped", None)])

    def test_duplicate_member(self):
        self.reject([("Example.app/file", None), ("Example.app/file", None)])

    def test_write_through_symlink(self):
        self.reject([("Example.app/link", "target"), ("Example.app/link/file", None)])

    def test_symlink_escape(self):
        self.reject([("Example.app/link", "../escaped")])

    def test_symlink_chain_escape(self):
        self.reject([("Example.app/sub/a", ".."), ("Example.app/b", "sub/a/../escaped")])


if __name__ == "__main__":
    unittest.main()
