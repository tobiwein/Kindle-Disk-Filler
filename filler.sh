#!/usr/bin/env bash
# filler.sh — Fill available disk space with labeled chunk files.
# Supports macOS and Linux, including USB and MTP-mounted devices.
#
# Usage: ./filler.sh [target-directory]
# If no directory is given, the current working directory is used.
#
# Press Ctrl+C at any time to abort. The partially written chunk
# will be removed automatically.

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
# Three standard chunk sizes used as denominations (like banknotes).
# Any fill target is expressed as a combination of these three sizes so that
# no odd-sized remainder file is ever created.
CHUNK_LARGE_MB=100
CHUNK_MEDIUM_MB=10
CHUNK_SMALL_MB=1
CHUNK_PREFIX="filler_chunk"
CHUNK_SUFFIX=".bin"
CHUNKS_SUBDIR="filler_chunks"  # Sub-folder created inside the target directory
# ──────────────────────────────────────────────────────────────────────────────

# Path of the chunk currently being written; used by the interrupt handler.
CURRENT_FILE=""

# Called on Ctrl+C (SIGINT) or SIGTERM.
# Removes the partially written chunk so no corrupt file is left behind.
cleanup() {
    echo ""   # Move past the progress bar line
    if [[ -n "$CURRENT_FILE" && -f "$CURRENT_FILE" ]]; then
        echo "Interrupted — removing incomplete chunk: $(basename "$CURRENT_FILE")"
        rm -f "$CURRENT_FILE"
    fi
    echo "Aborted."
    exit 1
}
trap cleanup INT TERM

# ─── Helper Functions ─────────────────────────────────────────────────────────

# Returns available space in MB for a given path.
get_available_mb() {
    local path="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: -m flag gives blocks of 1 MB
        df -m "$path" | awk 'NR==2 {print $4}'
    else
        # Linux: --block-size=1M normalizes output to MB
        df --block-size=1M "$path" | awk 'NR==2 {print $4}'
    fi
}

# Prints available device information using only tools bundled with the OS.
print_device_info() {
    local path="$1"
    local device
    device=$(df "$path" | awk 'NR==2 {print $1}')

    echo "Device path : $device"

    if [[ "$(uname)" == "Darwin" ]]; then
        # diskutil is built into macOS and provides rich device metadata.
        if command -v diskutil &>/dev/null; then
            diskutil info "$device" 2>/dev/null \
                | grep -E "Device / Media Name|Media Type|Protocol|Removable Media" \
                | sed 's/^[[:space:]]*/  /' \
                || true
        fi
    else
        # On Linux, check for FUSE/MTP mounts via the device string itself.
        if echo "$device" | grep -qiE "gvfs|mtp|fuse|aft"; then
            echo "  Type        : MTP / FUSE virtual filesystem"
        elif [[ "$device" == /dev/* ]]; then
            # lsblk is part of util-linux and available on virtually all distros.
            if command -v lsblk &>/dev/null; then
                local info
                info=$(lsblk -ndo TRAN,TYPE,MODEL "$device" 2>/dev/null || true)
                [[ -n "$info" ]] && echo "  $info"
            fi
            # Check the kernel's removable flag to identify USB/SD-card devices.
            local devname
            devname=$(basename "$device" | sed 's/[0-9]*$//')
            local removable_flag="/sys/block/${devname}/removable"
            if [[ -f "$removable_flag" ]] && [[ "$(cat "$removable_flag")" == "1" ]]; then
                echo "  Removable   : Yes (USB / SD card)"
            fi
        fi
    fi
}

# Counts filler chunk files that already exist in the target directory.
count_existing_chunks() {
    local dir="$1"
    find "$dir" -maxdepth 1 -name "${CHUNK_PREFIX}_*${CHUNK_SUFFIX}" 2>/dev/null \
        | wc -l | tr -d ' '
}

# Determines the next available sequential index so re-runs never overwrite
# existing chunks. Scans filenames for the four-digit index field.
get_next_index() {
    local dir="$1"
    local max=0
    while IFS= read -r file; do
        local num
        # Extract the numeric index, e.g. "filler_chunk_0007_100MB.bin" → 7.
        num=$(basename "$file" | grep -oE '_[0-9]{4}_' | head -1 | tr -d '_')
        # Force base-10 with 10# to avoid octal interpretation of leading zeros
        # (e.g. "0008" would otherwise be invalid octal and cause an error).
        if [[ -n "$num" && "10#$num" -gt "$max" ]]; then
            max="10#$num"
        fi
    done < <(find "$dir" -maxdepth 1 -name "${CHUNK_PREFIX}_*${CHUNK_SUFFIX}" 2>/dev/null)
    echo $((max + 1))
}

# Renders a single in-place progress bar for the overall write operation.
# Uses \r to overwrite the line on each update (no scrolling).
#   $1 — MB written so far across all chunks
#   $2 — total MB to write
#   $3 — current chunk number (1-based)
#   $4 — total number of chunks
draw_progress() {
    local written="$1"
    local total="$2"
    local chunk_num="$3"
    local total_chunks="$4"
    local bar_width=34

    local pct=$(( written * 100 / total ))
    local filled=$(( written * bar_width / total ))
    local empty=$(( bar_width - filled ))

    local bar="" i
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done

    # \r returns to the start of the line so the bar rewrites itself in-place.
    printf "\r  [%s] %d MB / %d MB (%d%%)  — chunk %d/%d   " \
        "$bar" "$written" "$total" "$pct" "$chunk_num" "$total_chunks"
}

# Writes a zero-filled file 1 MB at a time, updating the overall progress bar
# after each megabyte. Writing in 1 MB steps (rather than one large dd call)
# allows real-time progress feedback and immediate response to Ctrl+C.
#   $1 — destination file path
#   $2 — chunk size in MB
#   $3 — MB already written before this chunk starts (for cumulative display)
#   $4 — total MB to write across all chunks
#   $5 — current chunk number (for the chunk counter in the bar)
#   $6 — total number of chunks
write_chunk() {
    local filepath="$1"
    local size_mb="$2"
    local offset_mb="$3"
    local total_mb="$4"
    local chunk_num="$5"
    local total_chunks="$6"

    # Register the file globally so the interrupt handler can remove it.
    CURRENT_FILE="$filepath"

    local mb
    for ((mb = 1; mb <= size_mb; mb++)); do
        # Append one megabyte at a time; suppress dd's own output.
        dd if=/dev/zero bs=1M count=1 2>/dev/null >> "$filepath"
        draw_progress $((offset_mb + mb)) "$total_mb" "$chunk_num" "$total_chunks"
    done

    # Clear the global marker — file is now complete and must not be deleted.
    CURRENT_FILE=""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

echo "============================================================"
echo "  Disk Space Filler"
echo "============================================================"
echo ""

# Resolve target directory (argument or current directory).
TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# All chunk files go into a dedicated sub-folder so the device root stays tidy.
CHUNKS_DIR="$TARGET_DIR/$CHUNKS_SUBDIR"
mkdir -p "$CHUNKS_DIR"

echo "Target directory : $TARGET_DIR"
echo "Chunks folder    : $CHUNKS_DIR"
echo ""

# Show device details gathered without third-party tools.
echo "--- Device Information ---"
print_device_info "$TARGET_DIR" || true
echo ""

# Report current free space.
AVAILABLE_MB=$(get_available_mb "$TARGET_DIR")
echo "Available space  : ${AVAILABLE_MB} MB"

# Warn the user if existing chunks are present (they are kept, not overwritten).
EXISTING_CHUNKS=$(count_existing_chunks "$CHUNKS_DIR")
if [[ "$EXISTING_CHUNKS" -gt 0 ]]; then
    echo "Existing chunks  : $EXISTING_CHUNKS file(s) already present — new chunks will be appended."
fi
echo ""

# ─── User Prompt: How much space to leave free ────────────────────────────────

echo "How much space should remain free? (Recommended: 20–50 MB)"
echo "  [1] 20 MB (minimum safe buffer)"
echo "  [2] 50 MB (recommended)"
echo "  [3] Enter a custom amount"
echo ""
read -rp "Your choice [1/2/3]: " CHOICE

case "$CHOICE" in
    1) RESERVE_MB=20 ;;
    2) RESERVE_MB=50 ;;
    3)
        read -rp "Enter amount to keep free (MB): " RESERVE_MB
        # Validate that the input is a positive integer.
        if ! [[ "$RESERVE_MB" =~ ^[0-9]+$ ]] || [[ "$RESERVE_MB" -eq 0 ]]; then
            echo "Error: Please enter a positive whole number."
            exit 1
        fi
        ;;
    *)
        echo "Invalid choice — using default: 50 MB"
        RESERVE_MB=50
        ;;
esac

echo ""
echo "Will keep ${RESERVE_MB} MB free."

# ─── Calculate fill plan ──────────────────────────────────────────────────────

FILL_MB=$((AVAILABLE_MB - RESERVE_MB))

if [[ "$FILL_MB" -le 0 ]]; then
    echo ""
    echo "Nothing to do: available space (${AVAILABLE_MB} MB) is already at or below"
    echo "the requested reserve (${RESERVE_MB} MB)."
    exit 0
fi

# Break the fill target into standard denominations (100 MB / 10 MB / 1 MB)
# so that every chunk has a predictable, round size — no odd remainders.
N_LARGE=$(( FILL_MB / CHUNK_LARGE_MB ))
N_MEDIUM=$(( (FILL_MB % CHUNK_LARGE_MB) / CHUNK_MEDIUM_MB ))
N_SMALL=$(( FILL_MB % CHUNK_MEDIUM_MB ))
TOTAL_CHUNKS=$(( N_LARGE + N_MEDIUM + N_SMALL ))

echo ""
echo "--- Write Plan ---"
echo "  Total to write : ~${FILL_MB} MB"
[[ "$N_LARGE"  -gt 0 ]] && echo "  ${N_LARGE} × ${CHUNK_LARGE_MB} MB"
[[ "$N_MEDIUM" -gt 0 ]] && echo "  ${N_MEDIUM} × ${CHUNK_MEDIUM_MB} MB"
[[ "$N_SMALL"  -gt 0 ]] && echo "  ${N_SMALL} × ${CHUNK_SMALL_MB} MB"
echo "  Total files    : $TOTAL_CHUNKS"
echo ""
echo "  Press Ctrl+C at any time to abort cleanly."
echo ""

read -rp "Proceed? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted — no files were written."
    exit 0
fi

echo ""

# ─── Write Chunks ─────────────────────────────────────────────────────────────

# Start numbering after the highest existing index so re-runs are safe.
START_INDEX=$(get_next_index "$CHUNKS_DIR")

# Running total of MB written so far (used for the cumulative progress bar).
WRITTEN_MB=0
CHUNK_NUM=0

# Draw the initial empty bar so something is visible before the first byte.
draw_progress 0 "$FILL_MB" 1 "$TOTAL_CHUNKS"

# Helper: write one chunk of a given denomination and advance the counters.
write_denomination() {
    local size_mb="$1"
    CHUNK_NUM=$((CHUNK_NUM + 1))
    local index=$((START_INDEX + CHUNK_NUM - 1))
    local filename="${CHUNK_PREFIX}_$(printf '%04d' "$index")_${size_mb}MB${CHUNK_SUFFIX}"
    write_chunk "$CHUNKS_DIR/$filename" "$size_mb" "$WRITTEN_MB" "$FILL_MB" \
                "$CHUNK_NUM" "$TOTAL_CHUNKS"
    WRITTEN_MB=$((WRITTEN_MB + size_mb))
}

for ((i = 0; i < N_LARGE;  i++)); do write_denomination "$CHUNK_LARGE_MB";  done
for ((i = 0; i < N_MEDIUM; i++)); do write_denomination "$CHUNK_MEDIUM_MB"; done
for ((i = 0; i < N_SMALL;  i++)); do write_denomination "$CHUNK_SMALL_MB";  done

echo ""   # Newline after the completed progress bar

# ─── Summary ──────────────────────────────────────────────────────────────────

echo "Done."
FINAL_MB=$(get_available_mb "$TARGET_DIR")
echo "Remaining free space: ${FINAL_MB} MB"
echo ""
echo "To reclaim space, delete one or more chunk files from:"
echo "  $CHUNKS_DIR"
