"""Accept public sources only when they match the recorded archive and file hashes."""
import hashlib
import tarfile


def verify_file(path, expected):
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError(f'Public snapshot hash mismatch: {path}')


def prepare_snapshot(item, repo):
    archive = repo / item['snapshot']['archive']
    # Check even when reusing an existing extraction; never bless stale input.
    verify_file(archive, item['snapshot']['archive_sha256'])
    destination = archive.parent / 'source'
    if not destination.exists():
        with tarfile.open(archive) as tar:
            tar.extractall(destination, filter='data')
    roots = list(destination.iterdir())
    if len(roots) != 1 or not roots[0].is_dir() or roots[0].is_symlink():
        raise ValueError(f'Expected one public snapshot root: {destination}')
    root = roots[0].resolve()
    files = list(item['source_files'])
    version = item['version']
    files.append({'path': version['package_manifest'], 'sha256': version['package_manifest_sha256']})
    license = item['license']
    files.extend(license['files'] if 'files' in license else [license])
    for file in files:
        verify_file(root / file['path'], file['sha256'])
    return root
