ARCHIE.sh — Standalone Archival Reduction Tool
Overview

ARCHIE.sh is a standalone, directory-local video archival tool designed to reduce file sizes while preserving usable quality.

It is built for fast, repeatable batch processing with strong safety guarantees and clear, human-readable feedback.

ARCHIE is not a forensic preservation tool. It is intended for media that no longer requires evidentiary-grade integrity.

Core Principles
Non-destructive by default
Outputs must prove they earned their keep
If it doesn’t shrink, it doesn’t survive
All destructive actions require explicit user confirmation
Key Features
1. Archival Re-Encode Engine

ARCHIE processes video files in the current directory and produces reduced-size archival copies.

Four levels are available:

Level	Description
L1	Light shrink (higher quality, larger files)
L2	Balanced (recommended default)
L3	Aggressive compression
L4	Maximum shrink (storage-first priority)

All outputs are encoded using libx264 with tuned presets per level.

2. Intelligent Size Gate

Every output must pass a size check:

If the output is not smaller than the original, it is automatically deleted
Optional tolerance allows small overhead (e.g., container differences)

This guarantees that ARCHIE never produces useless results.

3. Resume-Safe Processing

ARCHIE can safely resume interrupted runs.

Detects existing archival outputs
Skips already processed files
Avoids re-encoding completed work
Maintains accurate batch statistics across restarts

This is critical for large batch operations.

4. Audio Handling Modes

Choose how audio is handled during re-encode:

Mode	Behavior
copy	Preserve original audio stream
aac	Re-encode to AAC (size reduction)
strip	Remove audio entirely
5. Metadata Handling

Three metadata strategies:

Mode	Behavior
sidecar_strip	Save metadata externally, strip from output
restore_common	Preserve common metadata fields
minimal_skip	Skip metadata capture entirely

Sidecars are stored in:

ARCHIE_META/
6. Archival Ledger

All successful outputs are recorded in:

ARCHIE_LEDGER.csv

Each entry includes:

source file
output file
encoding settings
size change
timestamp
metadata reference
ffmpeg log path

This provides full traceability and auditability.

7. Batch Space Savings Summary

At the end of each run, ARCHIE reports:

total source size
total kept archive size
net space saved
overall percent reduction

This is based on real byte totals, not estimates.

8. Tarball Packaging

Optionally bundle all surviving outputs into a single archive:

ARCHIVE_Lx_ARCHIVE_SET.tar

This step:

only includes successful outputs
does not recompress data
keeps provenance files separate
9. Controlled Destructive Cleanup

ARCHIE can optionally delete original files only if:

archival outputs exist
user passes multiple confirmation gates

This ensures safety even in automated workflows.

10. Progress and ETA Feedback

ARCHIE includes a rolling progress system:

per-file elapsed time
rolling average after initial samples
approximate ETA for remaining files

Designed for long-running batch visibility.

File Naming

Outputs follow this format:

ARCHIVE_Lx_####_<source_tail>.mkv
Lx = level (1–4)
#### = sequence number
<source_tail> = last portion of original filename

This ensures:

readability
collision resistance
restart-safe matching
Requirements

ARCHIE depends on the following tools:

ffmpeg
ffprobe
awk
sed
grep
stat
df
du
tar

Install example:

sudo apt update && sudo apt install ffmpeg -y
Usage

Run inside a directory containing video files:

bash archie.sh

Follow interactive prompts to:

select batch scope
choose archival level
configure audio and metadata
confirm execution
Directory Behavior

ARCHIE operates in-place:

reads from current directory
writes outputs to same directory
creates:
ARCHIE_META/
ARCHIE_LEDGER.csv
Safety Notes
Originals are never modified unless explicitly deleted
Outputs that fail size reduction are automatically removed
Metadata sidecars are for internal use only
This tool does not alter visual content (burn-ins remain)
Intended Use Cases
archival downsizing of large video collections
post-processing of non-critical footage
storage optimization workflows
batch media normalization
Not Intended For
forensic evidence preservation
legal chain-of-custody media
lossless archival requirements
Philosophy

ARCHIE is designed to be:

predictable
transparent
efficient
safe under interruption
honest about results

If it doesn’t save space, it doesn’t stay.
