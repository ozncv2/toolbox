"""Records what the image contains in a manifest that toolbox-doctor and users can read."""

import json
import os
import pathlib
import subprocess
import sys


def locked_tools(lock_paths, excluded):
    tools = {}
    for lock_path in lock_paths:
        for line in pathlib.Path(lock_path).read_text().splitlines():
            if line.strip() and not line.startswith("#"):
                _, name, version, *_ = line.split()
                if name == "uv" or name not in excluded:
                    tools[name] = version.split(":")[0]
    return tools


def apt_packages():
    output = subprocess.check_output(["dpkg-query", "-W", "-f=${Package} ${Version}\n"], text=True)
    return dict(line.split(" ", 1) for line in output.splitlines())


def python_versions():
    versions = {}
    for link in sorted(pathlib.Path("/opt/python").glob("3.*")):
        name = link.resolve().name
        versions[link.name] = name.split("-")[1]
    return versions


def main():
    output_path, *lock_paths = sys.argv[1:]
    excluded = sorted(item for item in os.environ.get("TOOLBOX_EXCLUDE", "").split(",") if item)
    manifest = {
        "version": os.environ.get("TOOLBOX_VERSION", "dev"),
        "excluded": excluded,
        "default_python": pathlib.Path("/opt/python/current").resolve().name.split("-")[1],
        "python": python_versions(),
        "tools": locked_tools(lock_paths, excluded),
        "apt": apt_packages(),
    }
    pathlib.Path(output_path).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
