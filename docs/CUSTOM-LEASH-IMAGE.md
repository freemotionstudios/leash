# Custom Leash Image

This document describes how to build and use a custom leash image with additional tools and non-root user support.

## Overview

The custom leash image extends the base leash runtime image to:

1. **Install additional tools** - Includes extra debugging, networking, and development tools that may be useful for advanced use cases
2. **Run as non-root user** - Configures a non-root user for improved security posture

## Building the Custom Image

### Quick Start

Build the custom image with default settings:

```bash
make docker-custom
```

Or use the build script directly:

```bash
./build/build-custom-image.sh
```

### Build Options

The build script supports several customization options:

```bash
./build/build-custom-image.sh [OPTIONS] [VERSION]

Options:
  --user USER        Custom user name (default: leash)
  --uid UID          Custom user UID (default: 1000)
  --gid GID          Custom user GID (default: 1000)
  --base-image IMG   Base leash image to use (default: leash/runtime-base:latest)
  --tag TAG          Custom tag for the built image (overrides VERSION)
  --push             Push the image after building
  -h, --help         Show this help message
```

### Examples

#### Build with custom user and UID

```bash
./build/build-custom-image.sh --user myuser --uid 1001 --gid 1001
```

#### Build and push to registry

```bash
./build/build-custom-image.sh --push v1.0.0
```

#### Build with a specific base image

```bash
./build/build-custom-image.sh --base-image public.ecr.aws/s5i7k8t3/strongdm/leash:latest
```

### Environment Variables

You can also configure the build using environment variables:

- `CUSTOM_LEASH_IMAGE` - Target image repository (default: `ghcr.io/strongdm/leash-custom`)
- `CUSTOM_USER` - Custom user name (default: `leash`)
- `CUSTOM_UID` - Custom user UID (default: `1000`)
- `CUSTOM_GID` - Custom user GID (default: `1000`)
- `BASE_LEASH_IMAGE` - Base leash image (default: `leash/runtime-base:latest`)

Example:

```bash
export CUSTOM_USER=myuser
export CUSTOM_UID=1001
./build/build-custom-image.sh
```

## Using the Custom Image

After building the custom image, you can use it with leash in several ways:

### 1. Via Command Line Flag

```bash
leash --leash-image ghcr.io/strongdm/leash-custom:latest -- codex
```

### 2. Via Environment Variable

```bash
export LEASH_IMAGE=ghcr.io/strongdm/leash-custom:latest
leash -- codex
```

### 3. Via Configuration File

Edit `~/.config/leash/config.toml`:

```toml
[leash]
leash_image = "ghcr.io/strongdm/leash-custom:latest"
```

Then run leash normally:

```bash
leash -- codex
```

## Additional Tools Included

The custom image includes the following additional tools beyond the base image:

### Networking Tools
- `nmap` - Network exploration and security auditing
- `netstat-nat` - Network statistics
- `socat` - Multipurpose relay for bidirectional data transfer

### Debugging Tools
- `strace` - System call tracer
- `ltrace` - Library call tracer
- `gdb` - GNU debugger

### Development Tools
- `git` - Version control
- `jq` - JSON processor
- `python3` - Python interpreter
- `python3-pip` - Python package installer

### File Utilities
- `tree` - Directory tree viewer
- `unzip` - Archive extraction
- `zip` - Archive creation

## Non-Root User Configuration

The custom image creates a non-root user with the following defaults:

- **Username**: `leash` (configurable via `--user`)
- **UID**: `1000` (configurable via `--uid`)
- **GID**: `1000` (configurable via `--gid`)

The directories `/log`, `/cfg`, and `/leash` are owned by this user.

### Important Notes

⚠️ **Note about privileges**: The leash daemon requires certain Linux capabilities (like `CAP_SYS_ADMIN` for BPF operations) to function properly. While the image is configured with a non-root user, it may still need to run with elevated privileges depending on the container runtime configuration.

When running with Docker, you might need to grant specific capabilities:

```bash
docker run --cap-add=SYS_ADMIN --cap-add=NET_ADMIN \
  --user 1000:1000 \
  ghcr.io/strongdm/leash-custom:latest
```

The leash CLI handles this automatically when launching containers.

## Customizing the Image Further

To add more tools or customize the image further, edit the `Dockerfile.custom` file:

```dockerfile
# Add your custom tools here
RUN apt-get update && apt-get install -y --no-install-recommends \
    your-package-here \
    another-package \
    && rm -rf /var/lib/apt/lists/*
```

Then rebuild:

```bash
make docker-custom
```

## Integration with CI/CD

You can integrate the custom image build into your CI/CD pipeline:

```bash
# Build the custom image
./build/build-custom-image.sh --tag "${CI_COMMIT_TAG}" --push

# Or use environment variables
export VERSION="${CI_COMMIT_TAG}"
export PUSH_IMAGE=1
./build/build-custom-image.sh
```

## Troubleshooting

### Base image not found

If you see an error about the base image not being found:

```bash
# Build the base images first
make docker-base
```

### Permission issues

If you encounter permission issues when running the custom image:

1. Check that the user ID matches your host user:
   ```bash
   ./build/build-custom-image.sh --uid $(id -u) --gid $(id -g)
   ```

2. Verify the container has necessary capabilities when running

### Custom tools not available

If custom tools aren't available in the container:

1. Verify the image was built successfully:
   ```bash
   docker images | grep leash-custom
   ```

2. Check that you're using the correct image:
   ```bash
   leash --leash-image ghcr.io/strongdm/leash-custom:latest -- codex shell
   ```

3. Verify tools are present:
   ```bash
   docker run --rm ghcr.io/strongdm/leash-custom:latest which jq
   ```

## See Also

- [CUSTOM-DOCKER-IMAGES.md](CUSTOM-DOCKER-IMAGES.md) - Guide for customizing the target (coder) image
- [CONFIG.md](CONFIG.md) - Configuration file documentation
- [DEVELOPMENT.md](DEVELOPMENT.md) - Development setup and guidelines
