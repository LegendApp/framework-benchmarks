"""Extract a benchmark tarball without traversal, special files, or symlink writes."""
import os
import pathlib
import shutil
import sys
import stat
import tarfile


def extract(archive, destination, bundle):
    destination = pathlib.Path(destination)
    if destination.exists():
        raise ValueError("Extraction destination already exists")
    with tarfile.open(archive, "r:gz") as source:
        members = source.getmembers()
        paths = {}
        for member in members:
            path = pathlib.PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != bundle:
                raise ValueError("Archive path escapes the expected bundle: " + member.name)
            if str(path) in paths:
                raise ValueError("Duplicate archive path: " + member.name)
            if not (member.isdir() or member.isfile() or member.issym()):
                raise ValueError("Unsupported archive member: " + member.name)
            if member.mode & 0o7000:
                raise ValueError("Special permission bits are not allowed")
            if member.issym():
                target = pathlib.PurePosixPath(member.linkname)
                normalized = os.path.normpath(str(path.parent / target))
                if target.is_absolute() or not normalized.startswith(bundle + "/"):
                    raise ValueError("Symlink escapes bundle: " + member.name)
            paths[str(path)] = member
        for name in paths:
            for parent in pathlib.PurePosixPath(name).parents:
                if str(parent) in paths and not paths[str(parent)].isdir():
                    raise ValueError("Archive writes through a non-directory: " + name)
        destination.mkdir(parents=True)
        # Write files before symlinks; extraction never follows archive-supplied links.
        for member in members:
            path = destination / member.name
            if member.isdir():
                path.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                path.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as input_file, path.open("xb") as output_file:
                    shutil.copyfileobj(input_file, output_file)
                path.chmod(member.mode & 0o777)
        for member in members:
            if member.issym():
                path = destination / member.name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(member.linkname)
        for member in members:
            if member.issym():
                # Lexically internal targets can still escape through another symlink.
                (destination / member.name).resolve().relative_to((destination / bundle).resolve())
        for member in reversed(members):
            if member.isdir():
                (destination / member.name).chmod(member.mode & 0o777)


def create(bundle, archive):
    bundle = pathlib.Path(bundle)
    with tarfile.open(archive, "w:gz", compresslevel=6) as target:
        def add(path):
            info = path.lstat()
            name = str(path.relative_to(bundle.parent))
            entry = tarfile.TarInfo(name)
            entry.mode = stat.S_IMODE(info.st_mode)
            entry.mtime = int(info.st_mtime)
            if path.is_symlink():
                entry.type = tarfile.SYMTYPE
                entry.linkname = os.readlink(path)
                target.addfile(entry)
            elif path.is_dir():
                entry.type = tarfile.DIRTYPE
                target.addfile(entry)
                for child in sorted(path.iterdir()):
                    add(child)
            elif path.is_file():
                # Store hard-linked regular files independently; preserve symlinks.
                entry.size = info.st_size
                with path.open("rb") as contents:
                    target.addfile(entry, contents)
            else:
                raise ValueError("Unsupported bundle member: " + str(path))
        add(bundle)


if __name__ == "__main__":
    {"create": create, "extract": extract}[sys.argv[1]](*sys.argv[2:])
