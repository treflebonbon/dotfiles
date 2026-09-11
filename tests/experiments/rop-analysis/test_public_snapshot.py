import hashlib
import io
import tarfile
import tempfile
import unittest
from pathlib import Path
from public_snapshot import prepare_snapshot


class PublicSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repo = Path(self.directory.name)
        self.archive = self.repo / 'source.tar.gz'
        files = {'src/main.rs': b'fn main() {}', 'Cargo.toml': b'[package]', 'LICENSE': b'license'}
        with tarfile.open(self.archive, 'w:gz') as tar:
            for path, contents in files.items():
                info = tarfile.TarInfo('project/' + path)
                info.size = len(contents)
                tar.addfile(info, io.BytesIO(contents))
        hashes = {path: hashlib.sha256(content).hexdigest() for path, content in files.items()}
        self.item = {'snapshot': {'archive': 'source.tar.gz',
                     'archive_sha256': hashlib.sha256(self.archive.read_bytes()).hexdigest()},
                     'source_files': [{'path': 'src/main.rs', 'sha256': hashes['src/main.rs']}],
                     'version': {'package_manifest': 'Cargo.toml', 'package_manifest_sha256': hashes['Cargo.toml']},
                     'license': {'path': 'LICENSE', 'sha256': hashes['LICENSE']}}

    def test_verified_archive_extracts_and_verified_destination_is_reused(self):
        root = prepare_snapshot(self.item, self.repo)
        self.assertEqual((root / 'src/main.rs').read_text(), 'fn main() {}')
        self.assertEqual(prepare_snapshot(self.item, self.repo), root)

    def test_wrong_archive_is_rejected_before_extraction(self):
        self.item['snapshot']['archive_sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            prepare_snapshot(self.item, self.repo)
        self.assertFalse((self.repo / 'source').exists())

    def test_matching_archive_with_wrong_selected_hash_is_rejected(self):
        self.item['source_files'][0]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            prepare_snapshot(self.item, self.repo)

    def test_existing_modified_source_is_rejected_without_overwriting_it(self):
        root = prepare_snapshot(self.item, self.repo)
        source = root / 'src/main.rs'
        source.write_text('modified')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            prepare_snapshot(self.item, self.repo)
        self.assertEqual(source.read_text(), 'modified')

    def test_existing_destination_does_not_skip_archive_check(self):
        prepare_snapshot(self.item, self.repo)
        self.item['snapshot']['archive_sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            prepare_snapshot(self.item, self.repo)

    def test_missing_selected_file_and_ambiguous_root_are_rejected(self):
        root = prepare_snapshot(self.item, self.repo)
        (root / 'src/main.rs').rename(root / 'src/renamed.rs')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            prepare_snapshot(self.item, self.repo)
        (self.repo / 'source/extra').mkdir()
        with self.assertRaisesRegex(ValueError, 'one public snapshot root'):
            prepare_snapshot(self.item, self.repo)

    def test_package_and_license_hashes_are_checked(self):
        root = prepare_snapshot(self.item, self.repo)
        for name in ('Cargo.toml', 'LICENSE'):
            with self.subTest(name=name):
                path = root / name
                original = path.read_bytes()
                path.write_text('modified')
                with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                    prepare_snapshot(self.item, self.repo)
                path.write_bytes(original)


if __name__ == '__main__':
    unittest.main()
