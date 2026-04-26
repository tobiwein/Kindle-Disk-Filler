# filler.ps1 - Fill available disk space with labeled chunk files.
# Supports Windows, including USB drives and MTP-mounted devices
# (phones, Kindles, cameras) accessible via a file system path.
#
# Usage: .\filler.ps1 [-TargetPath <path>]
# If -TargetPath is omitted, the current directory is used.
#
# Press Ctrl+C at any time to abort. The partially written chunk
# will be removed automatically.

param(
    [string]$TargetPath = (Get-Location).Path
)

# ─── Configuration ────────────────────────────────────────────────────────────
# Three standard chunk sizes used as denominations (like banknotes).
# Any fill target is expressed as a combination of these three sizes so that
# no odd-sized remainder file is ever created.
$ChunkLargeMB  = 100
$ChunkMediumMB = 10
$ChunkSmallMB  = 1
$ChunkPrefix   = "filler_chunk"
$ChunkSuffix   = ".bin"
$ChunksSubdir  = "filler_chunks"  # Sub-folder created inside the target directory
# ──────────────────────────────────────────────────────────────────────────────

# Returns available free space in MB for the given path.
function Get-AvailableMB {
    param([string]$Path)

    # Use the .NET DirectoryInfo class - works for regular drives and UNC/FUSE
    # paths alike. DriveInfo only works for lettered drives.
    $dir = [System.IO.DirectoryInfo]::new($Path)

    # Walk up to find the root of the volume (handles sub-directories too).
    $root = $dir
    while ($null -ne $root.Parent) { $root = $root.Parent }

    try {
        $drive = [System.IO.DriveInfo]::new($root.FullName)
        return [math]::Floor($drive.AvailableFreeSpace / 1MB)
    } catch {
        # DriveInfo may fail for MTP/virtual paths; fall back to WMI.
        $letter = $root.FullName.TrimEnd('\').TrimEnd('/')
        $vol = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$letter'" -ErrorAction SilentlyContinue
        if ($vol) {
            return [math]::Floor($vol.FreeSpace / 1MB)
        }
        Write-Warning "Could not determine available space - WMI query returned nothing."
        return 0
    }
}

# Prints device information using only Windows-built-in tools (no extra installs).
function Show-DeviceInfo {
    param([string]$Path)

    # Determine the drive root letter, if any.
    $root   = [System.IO.Path]::GetPathRoot($Path)
    $letter = $root.TrimEnd('\').TrimEnd('/')

    Write-Host "  Path         : $Path"

    if ($letter -match '^[A-Za-z]:$') {
        # For lettered drives, Get-Volume (built-in since Windows 8) provides
        # filesystem, label, and drive type without third-party tools.
        $vol = Get-Volume -DriveLetter $letter[0] -ErrorAction SilentlyContinue
        if ($vol) {
            Write-Host "  Volume label : $($vol.FileSystemLabel)"
            Write-Host "  File system  : $($vol.FileSystem)"
            Write-Host "  Drive type   : $($vol.DriveType)"
        }

        # Get-Disk + Get-Partition chain can identify USB vs. internal storage.
        try {
            $partition = Get-Partition -DriveLetter $letter[0] -ErrorAction Stop
            $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
            Write-Host "  Bus type     : $($disk.BusType)"
            Write-Host "  Media type   : $($disk.MediaType)"
            if ($disk.FriendlyName) {
                Write-Host "  Model        : $($disk.FriendlyName)"
            }
        } catch {
            # Removable / virtual drives may not appear in the storage stack.
        }
    } else {
        # MTP devices and UNC paths do not have a drive letter.
        Write-Host "  Type         : Virtual / MTP / UNC path (no drive letter)"
        Write-Host "  Note         : Device metadata is not available for this path type."
    }
}

# Returns the count of filler chunk files already present in the target directory.
function Get-ExistingChunkCount {
    param([string]$Dir)
    $pattern = "${ChunkPrefix}_*${ChunkSuffix}"
    return @(Get-ChildItem -Path $Dir -Filter $pattern -File -ErrorAction SilentlyContinue).Count
}

# Finds the highest existing chunk index and returns the next available number.
# This ensures re-runs append new chunks without overwriting existing ones.
function Get-NextChunkIndex {
    param([string]$Dir)
    $pattern = "${ChunkPrefix}_*${ChunkSuffix}"
    $files = Get-ChildItem -Path $Dir -Filter $pattern -File -ErrorAction SilentlyContinue
    $max = 0
    foreach ($f in $files) {
        # Chunk filenames follow the pattern: filler_chunk_NNNN_SIZEMb.bin
        if ($f.Name -match "_(\d{4})_") {
            $num = [int]$Matches[1]
            if ($num -gt $max) { $max = $num }
        }
    }
    return $max + 1
}

# Draws a single in-place progress bar for the overall write operation.
# Uses a carriage return to overwrite the line on each update (no scrolling).
#   $Written       - MB written so far across all chunks
#   $Total         - total MB to write
#   $ChunkNum      - current chunk number (1-based)
#   $TotalChunks   - total number of chunks
function Write-ProgressBar {
    param(
        [int]$Written,
        [int]$Total,
        [int]$ChunkNum,
        [int]$TotalChunks
    )
    $barWidth = 34
    $pct      = [math]::Floor($Written * 100 / $Total)
    $filled   = [math]::Floor($Written * $barWidth / $Total)
    $empty    = $barWidth - $filled

    $bar = ([string][char]0x2588) * $filled + ([string][char]0x2591) * $empty

    # `r (carriage return) moves back to start of line, rewriting it in-place.
    [Console]::Write("`r  [$bar] $Written MB / $Total MB ($pct%)  - chunk $ChunkNum/$TotalChunks   ")
}

# Writes a zero-filled file 1 MB at a time via a FileStream, updating the
# overall progress bar after each megabyte. Using a FileStream (instead of
# WriteAllBytes) lets us write incrementally so progress is visible in real
# time and Ctrl+C is handled cleanly.
#   $FilePath      - destination file path
#   $SizeMB        - chunk size in MB
#   $OffsetMB      - MB already written before this chunk (for cumulative display)
#   $TotalMB       - total MB to write across all chunks
#   $ChunkNum      - current chunk number (for the counter in the bar)
#   $TotalChunks   - total number of chunks
function Write-ChunkFile {
    param(
        [string]$FilePath,
        [int]$SizeMB,
        [int]$OffsetMB,
        [int]$TotalMB,
        [int]$ChunkNum,
        [int]$TotalChunks
    )

    # 1 MB zero-filled buffer reused for every write call.
    $buffer = New-Object byte[] (1MB)
    $stream = [System.IO.FileStream]::new(
        $FilePath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write
    )

    for ($mb = 1; $mb -le $SizeMB; $mb++) {
        $stream.Write($buffer, 0, $buffer.Length)
        Write-ProgressBar -Written ($OffsetMB + $mb) -Total $TotalMB `
                          -ChunkNum $ChunkNum -TotalChunks $TotalChunks
    }

    $stream.Close()
}

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================================"
Write-Host "  Disk Space Filler"
Write-Host "============================================================"
Write-Host ""

# Resolve to absolute path.
$TargetPath  = (Resolve-Path -LiteralPath $TargetPath).ProviderPath

# All chunk files go into a dedicated sub-folder so the device root stays tidy.
$ChunksPath  = Join-Path $TargetPath $ChunksSubdir
New-Item -ItemType Directory -Path $ChunksPath -Force | Out-Null

Write-Host "Target directory : $TargetPath"
Write-Host "Chunks folder    : $ChunksPath"
Write-Host ""

# Show device details using built-in Windows commands only.
Write-Host "--- Device Information ---"
Show-DeviceInfo -Path $TargetPath
Write-Host ""

# Report current free space.
$AvailableMB = Get-AvailableMB -Path $TargetPath
Write-Host "Available space  : $AvailableMB MB"

# Notify user if existing chunk files are present (they will not be touched).
$ExistingCount = Get-ExistingChunkCount -Dir $ChunksPath
if ($ExistingCount -gt 0) {
    Write-Host "Existing chunks  : $ExistingCount file(s) already present - new chunks will be appended."
}
Write-Host ""

# ─── User Prompt: How much space to leave free ────────────────────────────────

Write-Host "How much space should remain free? (Recommended: 20-50 MB)"
Write-Host "  [1] 20 MB (minimum safe buffer)"
Write-Host "  [2] 50 MB (recommended)"
Write-Host "  [3] Enter a custom amount"
Write-Host ""
$Choice = Read-Host "Your choice [1/2/3]"

switch ($Choice) {
    "1" { $ReserveMB = 20 }
    "2" { $ReserveMB = 50 }
    "3" {
        $input = Read-Host "Enter amount to keep free (MB)"
        if ($input -match '^\d+$' -and [int]$input -gt 0) {
            $ReserveMB = [int]$input
        } else {
            Write-Host "Invalid input - using default: 50 MB"
            $ReserveMB = 50
        }
    }
    default {
        Write-Host "Invalid choice - using default: 50 MB"
        $ReserveMB = 50
    }
}

Write-Host ""
Write-Host "Will keep $ReserveMB MB free."

# ─── Calculate fill plan ──────────────────────────────────────────────────────

$FillMB = $AvailableMB - $ReserveMB

if ($FillMB -le 0) {
    Write-Host ""
    Write-Host "Nothing to do: available space ($AvailableMB MB) is already at or below"
    Write-Host "the requested reserve ($ReserveMB MB)."
    exit 0
}

# Break the fill target into standard denominations (100 MB / 10 MB / 1 MB)
# so that every chunk has a predictable, round size - no odd remainders.
$NLarge      = [math]::Floor($FillMB / $ChunkLargeMB)
$NMedium     = [math]::Floor(($FillMB % $ChunkLargeMB) / $ChunkMediumMB)
$NSmall      = $FillMB % $ChunkMediumMB
$TotalChunks = $NLarge + $NMedium + $NSmall

Write-Host ""
Write-Host "--- Write Plan ---"
Write-Host "  Total to write : ~$FillMB MB"
if ($NLarge  -gt 0) { Write-Host "  $NLarge x $ChunkLargeMB MB" }
if ($NMedium -gt 0) { Write-Host "  $NMedium x $ChunkMediumMB MB" }
if ($NSmall  -gt 0) { Write-Host "  $NSmall x $ChunkSmallMB MB" }
Write-Host "  Total files    : $TotalChunks"
Write-Host ""
Write-Host "  Press Ctrl+C at any time to abort cleanly."
Write-Host ""

$Confirm = Read-Host "Proceed? [y/N]"
if ($Confirm -notmatch '^[Yy]$') {
    Write-Host "Aborted - no files were written."
    exit 0
}

Write-Host ""

# ─── Write Chunks ─────────────────────────────────────────────────────────────

# Start numbering after the highest existing index so re-runs are safe.
$StartIndex = Get-NextChunkIndex -Dir $ChunksPath

# Running total of MB written so far (used for the cumulative progress bar).
$WrittenMB   = 0
$ChunkNum    = 0
$CurrentFile = $null

# Draw the initial empty bar so something is visible before the first byte.
Write-ProgressBar -Written 0 -Total $FillMB -ChunkNum 1 -TotalChunks $TotalChunks

# Helper scriptblock: write one chunk of a given denomination and advance counters.
$WriteDenomination = {
    param([int]$SizeMB)
    $script:ChunkNum++
    $Index    = $StartIndex + $script:ChunkNum - 1
    $FileName = "${ChunkPrefix}_$("{0:D4}" -f $Index)_${SizeMB}MB${ChunkSuffix}"
    $FilePath = Join-Path $ChunksPath $FileName

    $script:CurrentFile = $FilePath
    Write-ChunkFile -FilePath $FilePath -SizeMB $SizeMB `
                    -OffsetMB $script:WrittenMB -TotalMB $FillMB `
                    -ChunkNum $script:ChunkNum -TotalChunks $TotalChunks
    $script:CurrentFile = $null
    $script:WrittenMB  += $SizeMB
}

# The try/finally guarantees cleanup even if the script is interrupted.
# PowerShell executes the finally block before honoring Ctrl+C termination.
try {
    for ($i = 0; $i -lt $NLarge;  $i++) { & $WriteDenomination $ChunkLargeMB  }
    for ($i = 0; $i -lt $NMedium; $i++) { & $WriteDenomination $ChunkMediumMB }
    for ($i = 0; $i -lt $NSmall;  $i++) { & $WriteDenomination $ChunkSmallMB  }

    Write-Host ""   # Newline after the completed progress bar
} finally {
    # If $CurrentFile is still set, the write was interrupted mid-chunk.
    # Delete the partial file to avoid leaving corrupt data on the device.
    if ($null -ne $CurrentFile -and (Test-Path $CurrentFile)) {
        Write-Host ""
        Write-Host "Interrupted - removing incomplete chunk: $(Split-Path $CurrentFile -Leaf)"
        Remove-Item $CurrentFile -Force
        Write-Host "Aborted."
        exit 1
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────────

Write-Host "Done."
$FinalMB = Get-AvailableMB -Path $TargetPath
Write-Host "Remaining free space: $FinalMB MB"
Write-Host ""
Write-Host "To reclaim space, delete one or more chunk files from:"
Write-Host "  $ChunksPath"
Write-Host ""
