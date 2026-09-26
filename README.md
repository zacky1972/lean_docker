# lean_docker

`lean_docker` is intended to be imported as a subproject of a Lean project. It
provides a small, reproducible Lean development environment for formalizing a
type system and proving its properties.

The Dockerfile is therefore located at:

```text
PROJECT_ROOT/lean_docker/Dockerfile
```

All Docker build commands must use `PROJECT_ROOT` as the build context. This is
important because the Dockerfile reads `lean-toolchain` and copies source files
from the consuming project, not from the `lean_docker` subdirectory.

The image contains:

- Debian Bookworm Slim
- `elan`, the Lean toolchain manager
- the Lean toolchain selected by the project's `lean-toolchain` file
- `lake`, supplied by the selected Lean toolchain
- Git, for downloading Lake dependencies
- CA certificates for secure downloads

It deliberately does not embed Mathlib or select a Lean version independently
of the project. Dependencies belong in the Lake project, and the Lean version
belongs in `lean-toolchain`.

The Dockerfile supports both `linux/amd64` and `linux/arm64`.

## Expected project layout

Import or check out `lean_docker` under the project that will use it. A minimal
layout is:

```text
PROJECT_ROOT/
├── lean-toolchain
└── lean_docker/
    ├── Dockerfile
    └── README.md
```

A normal project will also contain `lakefile.toml` or `lakefile.lean` and its
Lean source files:

```text
PROJECT_ROOT/
├── lean-toolchain
├── lakefile.toml
├── Main.lean
├── MyProject/
│   └── TypeSystem.lean
└── lean_docker/
    ├── Dockerfile
    └── README.md
```

The exact Lean source layout is controlled by the consuming project.

## Prerequisites

Install Docker Desktop or Docker Engine with BuildKit support.

## Select the Lean toolchain

Create a `lean-toolchain` file containing exactly one toolchain name.

For a reproducible project, use an explicit release:

```text
leanprover/lean4:vX.Y.Z
```

Replace `vX.Y.Z` with the Lean release required by the project. If an existing
Lean project already has this file, use it unchanged.

The Docker build installs that toolchain. At run time, `elan` also reads the
same file when choosing `lean` and `lake`.

## Use the latest Lean release

The word "latest" can mean either the latest stable release or the latest
nightly development snapshot. For most type-system work, use the latest stable
release unless a required Lean feature exists only in nightly.

### Latest stable release

Put the following single line in `PROJECT_ROOT/lean-toolchain`:

```text
stable
```

Then build from `PROJECT_ROOT`:

```sh
docker build \
  --file lean_docker/Dockerfile \
  --tag lean-type-system \
  .
```

`elan` resolves `stable` to the newest stable Lean release available when the
toolchain-installation layer is executed.

### Refresh an existing image to the newest stable release

Docker may reuse the previous toolchain layer when neither `lean-toolchain` nor
the Dockerfile has changed. To force only that layer and the layers after it to
run again, provide a new refresh token:

```sh
docker build \
  --file lean_docker/Dockerfile \
  --build-arg LEAN_TOOLCHAIN_REFRESH="$(date -u +%Y%m%d%H%M%S)" \
  --tag lean-type-system \
  .
```

The token has no semantic meaning. Its only purpose is to invalidate Docker's
cached Lean-installation layer. Earlier Debian and `elan` download layers can
remain cached.

Alternatively, `--no-cache` also forces an update, but it rebuilds every layer
and downloads more than necessary:

```sh
docker build \
  --no-cache \
  --file lean_docker/Dockerfile \
  --tag lean-type-system \
  .
```

Verify the version selected by the rebuilt image:

```sh
docker run --rm lean-type-system lean --version
```

### Latest nightly snapshot

To follow the latest Lean development snapshot, put this in `lean-toolchain`:

```text
nightly
```

Build or refresh the image using the same command and
`LEAN_TOOLCHAIN_REFRESH` argument shown above. Nightly may contain features not
yet available in a stable release, but it can also introduce incompatible
changes.

### Pin the version after testing

`stable` and `nightly` are moving channels. Two clean builds performed at
different times may therefore install different Lean versions.

After confirming that a particular stable release works, replace `stable` in
`lean-toolchain` with the version reported by `lean --version`, using the
explicit form:

```text
leanprover/lean4:vX.Y.Z
```

Commit that `lean-toolchain` file to the consuming project. This is the
recommended mode for CI, published proofs, and any work that must remain
reproducible.

For a reproducible nightly build, use a dated nightly name instead of the
moving `nightly` channel:

```text
nightly-YYYY-MM-DD
```

### Update Lean libraries after changing Lean

Changing the Lean toolchain can require compatible revisions of Lake
dependencies. After rebuilding the image, enter the container and run:

```sh
lake update
lake build
```

Review and commit the resulting `lake-manifest.json` changes when the project
uses that manifest. If the project uses Mathlib, select a Mathlib revision that
supports the chosen Lean release and then retrieve its cache with:

```sh
lake update
lake exe cache get
lake build
```

## Build the image

Change to the consuming project's root directory and specify the nested
Dockerfile with `--file`:

```sh
cd PROJECT_ROOT
docker build \
  --file lean_docker/Dockerfile \
  --tag lean-type-system \
  .
```

The final `.` is significant: it makes `PROJECT_ROOT`, rather than
`PROJECT_ROOT/lean_docker`, the build context.

The first build downloads `elan` and the selected Lean toolchain. Later builds
can reuse Docker's cached layers as long as `lean-toolchain` does not change.

The build verifies the downloaded `elan` archive with a pinned SHA-256 digest.

## Start an interactive container

To open a shell with the project version copied into the image:

```sh
docker run --rm --interactive --tty lean-type-system
```

Confirm the installed tools with:

```sh
lean --version
lake --version
elan show
```

## Work on files from the host

During development, mount the current project directory at `/workspace`:

```sh
docker run --rm --interactive --tty \
  --mount type=bind,source="$PWD",target=/workspace \
  lean-type-system
```

Changes made in `/workspace` are then visible on both the host and in the
container.

On Linux, the container uses UID 1000. If the host project is not writable by
that UID, either adjust the host permissions or run with the host user's numeric
UID and GID:

```sh
docker run --rm --interactive --tty \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp/lean-home \
  --mount type=bind,source="$PWD",target=/workspace \
  lean-type-system
```

The default UID normally works without additional configuration on Docker
Desktop for macOS.

## Build and check the Lean project

Inside the container, use Lake normally:

```sh
lake update
lake build
```

For a single source file that does not need a Lake project:

```sh
lean Path/To/File.lean
```

For a formalized type system, a typical project may contain definitions for
syntax, contexts, substitution, typing judgments, operational semantics, and
metatheoretic results such as weakening, substitution, progress, and
preservation. These are ordinary Lean modules and do not require additional
system packages in the container.

## Add Lean libraries

Declare Lean libraries in `lakefile.toml` or `lakefile.lean`; do not install
them in the Dockerfile.

After changing the dependency declarations, run:

```sh
lake update
lake build
```

If the project uses Mathlib, download its precompiled cache before building:

```sh
lake exe cache get
lake build
```

Mathlib is optional. A small type-system development can begin with Lean's core
and standard libraries and add other packages only when they provide something
the formalization actually needs.

## Run one command without opening a shell

Build the mounted project:

```sh
docker run --rm \
  --mount type=bind,source="$PWD",target=/workspace \
  lean-type-system \
  lake build
```

Check one file:

```sh
docker run --rm \
  --mount type=bind,source="$PWD",target=/workspace \
  lean-type-system \
  lean Path/To/File.lean
```

## Apple Silicon

On an Apple Silicon Mac, Docker automatically selects the native
`linux/arm64` build. No `--platform linux/amd64` option is needed.

To build a specific platform explicitly:

```sh
docker build \
  --platform linux/arm64 \
  --file lean_docker/Dockerfile \
  --tag lean-type-system \
  .
```

## Multi-platform image

To publish both supported architectures, use `buildx` with a registry-qualified
image name:

```sh
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --file lean_docker/Dockerfile \
  --tag REGISTRY/OWNER/lean-type-system:TAG \
  --push \
  .
```

Replace `REGISTRY`, `OWNER`, and `TAG` with the intended registry coordinates.

## Updating `elan`

The Dockerfile pins both the `elan` version and the SHA-256 digest for each
supported architecture. Updating `ELAN_VERSION` therefore also requires
updating both digests from the corresponding official `elan` release assets.

Do not change only the version number: the integrity check will correctly fail
if the new archive does not match the old digest.

## Troubleshooting

### `lean-toolchain` is missing

The Docker build intentionally requires this file at
`PROJECT_ROOT/lean-toolchain`:

```text
failed to calculate checksum ... lean-toolchain: not found
```

Create `lean-toolchain` in the consuming project's root directory. Then run the
build from that directory with `--file lean_docker/Dockerfile` and `.` as the
build context.

### The requested Lean toolchain cannot be downloaded

Check the exact contents of `lean-toolchain` and confirm that the named Lean
release exists. The file must not contain comments or additional settings.

### Lake cannot download a dependency

Confirm that the container has network access and that the dependency revision
in the Lake manifest or project configuration exists. Git is already installed
in the image.

### Build results disappeared

The `--rm` option removes the container after it exits. Source files and
`.lake` build results persist only when `/workspace` is bind-mounted from the
host or stored in another volume.

## Design principles

This image keeps three responsibilities separate:

1. Docker supplies a small Linux execution environment.
2. `elan` installs and selects Lean.
3. The Lean project selects its toolchain and Lake dependencies.

This avoids relying on an unmaintained third-party Lean image and prevents the
container image from becoming a second, conflicting source of the project's
Lean version.

## License

Copyright (c) 2026 University of Kitakyushu

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
You may obtain a copy of the License at <http://www.apache.org/licenses/LICENSE-2.0>.

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and limitations under the License.

