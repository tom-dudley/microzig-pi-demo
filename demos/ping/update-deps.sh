#!/bin/bash
set -e

REPO="tom-dudley/microzig"
BRANCH="cyw43-sdpcm-minimal"

echo "Fetching latest commit from $REPO@$BRANCH..."
COMMIT=$(curl -s "https://api.github.com/repos/$REPO/commits/$BRANCH" | grep '"sha"' | head -1 | cut -d'"' -f4)

if [ -z "$COMMIT" ]; then
    echo "Error: Could not fetch commit hash"
    exit 1
fi

echo "Latest commit: $COMMIT"

# Update build.zig.zon - replace either .path or .url, remove any existing hash
cat > build.zig.zon << EOF
.{
    .name = .wifi_ping_demo,
    .version = "0.0.0",
    .fingerprint = 0xcfac24ddfbf87365,
    .minimum_zig_version = "0.14.0",
    .dependencies = .{
        .microzig = .{
            .url = "git+https://github.com/$REPO.git#$COMMIT",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
EOF

echo "Running zig build to get content hash..."
rm -rf .zig-cache

# Capture the expected hash from build output
HASH=$(zig build 2>&1 | grep 'expected .hash' | sed 's/.*expected .hash = "\([^"]*\)".*/\1/')

if [ -z "$HASH" ]; then
    echo "Error: Could not determine content hash"
    exit 1
fi

echo "Content hash: $HASH"

# Add the hash to build.zig.zon
cat > build.zig.zon << EOF
.{
    .name = .wifi_ping_demo,
    .version = "0.0.0",
    .fingerprint = 0xcfac24ddfbf87365,
    .minimum_zig_version = "0.14.0",
    .dependencies = .{
        .microzig = .{
            .url = "git+https://github.com/$REPO.git#$COMMIT",
            .hash = "$HASH",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
EOF

echo "Verifying build..."
zig build

echo "Done! Updated to $REPO@${COMMIT:0:8}"
