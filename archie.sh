#!/usr/bin/env bash

# -----------------------------------------------------------------------------------------
# !!! CRITICAL: THIS FILE IS A STANDALONE TOOL
# !!! CRITICAL: IT DOES NOT DEPEND ON factory.sh OR ANY FACTORY HELPERS
# !!! CRITICAL: LEAVE THE SHEBANG ABOVE AS THE FIRST TOP LINE
# -----------------------------------------------------------------------------------------
#                                ARCHIE.SH  v2.1
# -----------------------------------------------------------------------------------------
# PURPOSE:
# - Standalone archival reduction tool for fast drop-in directory work.
# - Re-encode video files that no longer need evidentiary-grade treatment.
# - Create smaller archival copies using one of four reduction levels.
# - Optionally keep audio, re-encode audio, or strip audio entirely.
# - Optionally capture original metadata into sidecars for internal reference.
# - Optionally tar the surviving archival outputs.
# - Optionally delete originals ONLY after repeated warning gates.
#
# DESIGN PHILOSOPHY:
# - NON-DESTRUCTIVE BY DEFAULT
# - OUTPUTS MUST PROVE THEY EARNED THEIR KEEP
# - IF AN ENCODE DOES NOT GET SMALLER, ARCHIE DUMPS IT
# - DELETES REQUIRE MULTIPLE HUMAN CONFIRMATION GATES
#
# IMPORTANT:
# - This is an archival shrink tool, not a forensic-preservation tool.
# - This does NOT remove visible burn-ins or text embedded in the picture.
# - Metadata sidecars are for INTERNAL reference only.
# -----------------------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob

# ------------------ COLORS ------------------
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
WHITE='\033[1;37m'
BWHITE='\033[1;37m'
NC="\033[0m"

# Stable semantic warning colors
RE=$'\033[1;1;31m'
REB=$'\033[5;1;31m'
YE=$'\033[1;1;33m'
YEB=$'\033[5;1;33m'
GR=$'\033[1;32m'
BW=$'\033[1;37m'

# ------------------ DEFAULTS ------------------
ARCHIE_VERSION="2.1"
ARCHIE_DEFAULT_LEVEL=2
ARCHIE_DEFAULT_AUDIO_MODE="aac"
ARCHIE_DEFAULT_AAC_BITRATE="128k"
ARCHIE_DEFAULT_METADATA_MODE="sidecar_strip"
ARCHIE_SEQUENCE_PAD=4
ARCHIE_NO_GAIN_MODE="dump"
ARCHIE_SIZE_TOLERANCE_PERCENT=0

# ========================================================
# #MARKER: FILENAME SHORTENING DEFAULTS
# ========================================================
# PURPOSE:
# - Keep ARCHIE output names short enough to stay readable
# - Preserve meaningful front-of-name intent when it exists
# - Continue collapsing long zero-padded camera junk safely
#
# DESIGN RULE:
# - ONE shared helper must decide the shortened stem
# - Output generation and resume matching must use that same helper
#
# DEFAULT BEHAVIOR:
# - Enabled by default
# - Preserve a small meaningful prefix when present
# - Preserve a tail slice for recognition / matching
#
# DISABLE OPTIONS:
# - Set ENABLE to 0 to fully disable shortening
# - Large keep values can also make shortening effectively disappear
#   for ordinary filenames, but explicit disable is cleaner / preferred
# ========================================================
ARCHIE_NAME_SHORTEN_ENABLE=1
ARCHIE_NAME_SHORTEN_KEEP_PREFIX=2
ARCHIE_NAME_SHORTEN_KEEP_TAIL=12

ARCHIE_META_DIR="ARCHIE_META"
ARCHIE_LEDGER="ARCHIE_LEDGER.csv"

# ========================================================
# #MARKER: CUT-FRIENDLY / PRE-FACTORY DEFAULTS
# ========================================================
# PURPOSE:
# - Allow ARCHIE to optionally produce more cut-friendly outputs
# - Help FACTORY keyframe suitability checks pass on first inspection
# - Avoid unnecessary follow-up REKEY work when ARCHIE already did
#   the heavy re-encode job
#
# IMPORTANT:
# - This mode is INDEPENDENT from L1 / L2 / L3 / L4
# - Levels still control squeeze / quality balance
# - This toggle only controls GOP / keyframe targeting behavior
#
# DESIGN RULE:
# - OFF by default so normal ARCHIE archival work keeps its current
#   shrink-first behavior unless user explicitly asks otherwise
# ========================================================
ARCHIE_DEFAULT_CUT_FRIENDLY_MODE="off"

ARCHIE_SELECTED_AUDIO_MODE=""
ARCHIE_SELECTED_METADATA_MODE=""
ARCHIE_SELECTED_CUT_FRIENDLY_MODE=""
# ------------------ DEFAULTS ------------------
# ------------------ PROGRESS / ETA TRACKING ------------------
# ========================================================
# ARCHIE ROLLING PROGRESS / ETA STATE
# ========================================================
# PURPOSE:
# - Give The Yellow "Please Stand By" Line Real Context
# - Track Per-File Elapsed Seconds
# - Build A Rolling Average After A Few Completed Files
# - Show A Rough ETA For Remaining Files
#
# IMPORTANT:
# - ETA is intentionally approximate
# - Different files can vary wildly by:
#     duration / resolution / codec / level / audio mode
# - So we do NOT show ETA immediately
# - We wait until enough files have completed to form a clue
#
# RULE:
# - No ETA for first 2 completed files
# - Start showing ETA after 3 completed files
# ========================================================
ARCHIE_PROGRESS_DONE_COUNT=0
ARCHIE_PROGRESS_TOTAL_SECONDS=0
ARCHIE_PROGRESS_TOTAL_FILES=0
ARCHIE_PROGRESS_CURRENT_INDEX=0
ARCHIE_PROGRESS_LAST_ELAPSED=0
# -------/\----------- DEFAULTS ------/\------------

# ------------------ TWISTED-LITE (ARCHIE) ------------------
# ========================================================
# #MARKER: TWISTED-LITE ENGINE (ARCHIE-SAFE)
# ========================================================
# PURPOSE:
# - Provide a lightweight, safe version of the Factory twisted engine
# - Add visual variety during long archival runs
# - Keep ARCHIE lean (no full menu system, no F-key capture)
#
# DESIGN RULES:
# - Semantic warning colors NEVER change:
#     RE / REB / YE / YEB / GR / BW
# - Only decorative display palette is remapped:
#     RED GREEN YELLOW BLUE MAGENTA CYAN WHITE BWHITE
#
# OPERATION:
# - Optional toggle before run
# - Can cycle palettes:
#     sequential OR random
# - Flip occurs BETWEEN FILES ONLY (safe, no spinner corruption)
#
# LIMITS:
# - Cycle interval: 1–10 files (clamped)
# - Preset count intentionally small and curated
# ========================================================

ARCHIE_TWIST_ENABLE=0
ARCHIE_TWIST_MODE="sequential"   # sequential | random
ARCHIE_TWIST_EVERY_N_FILES=5
ARCHIE_TWIST_INDEX=0

# ----- APPLY COLOR MAP (SAFE REMAP) -----------------------
archie_apply_palette() {
    local r="$1" g="$2" y="$3" b="$4" m="$5" c="$6" w="$7" bw="$8"

    RED="$r"
    GREEN="$g"
    YELLOW="$y"
    BLUE="$b"
    MAGENTA="$m"
    CYAN="$c"
    WHITE="$w"
    BWHITE="$bw"

    NC=$'\033[0m'

    # ----- KEEP SEMANTIC COLORS LOCKED --------------------
    RE=$'\033[1;1;31m'
    REB=$'\033[5;1;31m'
    YE=$'\033[1;1;33m'
    YEB=$'\033[5;1;33m'
    GR=$'\033[1;32m'
    BW=$'\033[1;37m'
}

# ----- PRESET PALETTES ------------------------------------
# NOTE:
# - Mix of bold + subdued for different environments
# - All are pre-validated (no unreadable combos)

archie_palette_apply_by_name() {
    local name="${1,,}"

    case "$name" in
        classic) #this one looks like oem so whay does it need a preset
            archie_apply_palette \
                $'\033[1;31m' $'\033[1;32m' $'\033[1;33m' $'\033[1;34m' \
                $'\033[1;35m' $'\033[1;36m' $'\033[1;37m' $'\033[1;97m'
            ;;
        christmas) # fixed: proper red + green palette (no yellow)
            archie_apply_palette \
                $'\033[1;31m' $'\033[1;32m' $'\033[1;32m' $'\033[1;31m' \
                $'\033[1;31m' $'\033[1;32m' $'\033[1;37m' $'\033[1;97m'
            ;;
        contrast) # fixed: intentionally harsh / high-contrast palette
            archie_apply_palette \
                $'\033[1;91m' $'\033[0;32m' $'\033[1;93m' $'\033[0;34m' \
                $'\033[1;95m' $'\033[0;36m' $'\033[1;97m' $'\033[0;90m'
            ;;
        muted) #this one looks good and dim
            archie_apply_palette \
                $'\033[0;31m' $'\033[0;32m' $'\033[0;33m' $'\033[0;34m' \
                $'\033[0;35m' $'\033[0;36m' $'\033[0;37m' $'\033[1;37m'
            ;;
        ice) # reworked: cold, sharp, high-contrast "frozen" palette
            archie_apply_palette \
                $'\033[1;96m' $'\033[0;36m' $'\033[1;97m' $'\033[0;34m' \
                $'\033[1;94m' $'\033[1;96m' $'\033[1;97m' $'\033[0;37m'
            ;;
        danger) #this one looks good
            archie_apply_palette \
                $'\033[1;91m' $'\033[1;31m' $'\033[1;93m' $'\033[1;35m' \
                $'\033[1;95m' $'\033[1;33m' $'\033[1;37m' $'\033[1;97m'
            ;;
        mono) #this one looks good
            archie_apply_palette \
                $'\033[0;37m' $'\033[1;37m' $'\033[0;37m' $'\033[0;90m' \
                $'\033[0;37m' $'\033[1;37m' $'\033[0;37m' $'\033[1;37m'
            ;;
        twisted) #this one looks good
            archie_apply_palette \
                $'\033[1;36m' $'\033[1;35m' $'\033[1;31m' $'\033[1;33m' \
                $'\033[1;32m' $'\033[1;94m' $'\033[1;97m' $'\033[1;93m'
            ;;
        *)
            archie_palette_apply_by_name "classic"
            ;;
    esac
}

ARCHIE_TWIST_PRESETS=(classic christmas contrast muted ice danger mono twisted)

# ----- PALETTE CYCLER -------------------------------------
archie_twist_cycle() {
    (( ARCHIE_TWIST_ENABLE == 1 )) || return 0

    local total="${#ARCHIE_TWIST_PRESETS[@]}"
    local name

    if [[ "$ARCHIE_TWIST_MODE" == "random" ]]; then
        name="${ARCHIE_TWIST_PRESETS[$((RANDOM % total))]}"
    else
        name="${ARCHIE_TWIST_PRESETS[$((ARCHIE_TWIST_INDEX % total))]}"
        ARCHIE_TWIST_INDEX=$((ARCHIE_TWIST_INDEX + 1))
    fi

    archie_palette_apply_by_name "$name"

    echo -e "${CYAN} = = > Twisted-Lite Palette Flip:${NC} ${YELLOW}$name${NC}"
    echo
}

# ----- USER CONFIG (LIGHT PROMPT) --------------------------
archie_twist_configure() {
    local mode_input n_input

    echo -e "${CYAN} = = > Twisted-Lite Display Mode:${NC}"
    echo -e "${CYAN}     1) Off${NC}"
    echo -e "${CYAN}     2) Sequential Palette Cycle${NC}"
    echo -e "${CYAN}     3) Random Palette Cycle${NC}"
    echo

	echo -e "${YELLOW} = = > Select [1-3 | Enter=off] (Default: off): ${NC}"
	read -r mode_input
	mode_input="${mode_input//[[:space:]]/}"

    case "$mode_input" in
        2)
            ARCHIE_TWIST_ENABLE=1
            ARCHIE_TWIST_MODE="sequential"
            ;;
        3)
            ARCHIE_TWIST_ENABLE=1
            ARCHIE_TWIST_MODE="random"
            ;;
        *)
            ARCHIE_TWIST_ENABLE=0
            return 0
            ;;
    esac

    echo
    echo -e "${CYAN} = = > Flip Palette Every N Completed Files (1-10):${NC}"
    echo -e "${YELLOW} = = > Default:${NC} ${GREEN}${ARCHIE_TWIST_EVERY_N_FILES}${NC}"
    echo

    echo -ne "${YELLOW} = = > Enter N: ${NC}"
    read -r n_input
    n_input="${n_input//[[:space:]]/}"

    if [[ "$n_input" =~ ^[0-9]+$ ]]; then
        (( n_input < 1 )) && n_input=1
        (( n_input > 10 )) && n_input=10
        ARCHIE_TWIST_EVERY_N_FILES="$n_input"
    fi

    echo -e "${CYAN} = = > Twisted-Lite Active:${NC} ${GREEN}${ARCHIE_TWIST_MODE}${NC} ${CYAN}every${NC} ${YELLOW}${ARCHIE_TWIST_EVERY_N_FILES}${NC} ${CYAN}file(s)${NC}"
    echo
}
# -------/\----------- TWISTED-LITE END ------/\------------

# ------------------ ARCHIE EASTER EGG ------------------
# ========================================================
# #MARKER: ARCHIE EASTER EGG (MASCOT DISPLAY ENGINE)
# ========================================================
# PURPOSE:
# - Provide a fun visual break during long archival runs
# - Trigger only on large batches (default: 50+ files)
# - Display external ASCII art if available
# - Fall back to a small built-in mascot if not
#
# DESIGN RULES:
# - NEVER interfere with encoding process
# - ONLY trigger between files (safe display window)
# - Keep runtime delay short and controlled
#
# CONFIG:
# - Enabled by default (can be disabled easily)
# - Trigger every N completed files
#
# NOTE:
# - External file allows customization (logo, mascot, etc.)
# - No dependency on external tools beyond cat
# ========================================================

ARCHIE_EGG_ENABLE=1
ARCHIE_EGG_MIN_FILES=50
ARCHIE_EGG_EVERY_N_FILES=10
ARCHIE_EGG_FILE="ARCHIE_ASCII.txt"

# ----- DISPLAY EASTER EGG -------------------------------
archie_show_easter_egg() {
    (( ARCHIE_EGG_ENABLE == 1 )) || return 0

    # Only trigger on sufficiently large batches
    (( ARCHIE_PROGRESS_TOTAL_FILES >= ARCHIE_EGG_MIN_FILES )) || return 0

    # Only trigger at defined interval
    if ! (( ARCHIE_PROGRESS_DONE_COUNT > 0 )) || \
       ! (( ARCHIE_PROGRESS_DONE_COUNT % ARCHIE_EGG_EVERY_N_FILES == 0 )); then
        return 0
    fi

    echo

    # ----------------------------------------------------
    # EXTERNAL ASCII (USER CUSTOMIZABLE)
    # ----------------------------------------------------
    if [[ -f "$ARCHIE_EGG_FILE" ]]; then
        echo -e "${CYAN} = = > Displaying Custom ASCII:${NC} ${YELLOW}$ARCHIE_EGG_FILE${NC}"
        echo
        archie_play_ascii_scroll "$ARCHIE_EGG_FILE" 2 0.015 0.30

    else
        # ------------------------------------------------
        # BUILT-IN FALLBACK (SMALL BODY CAT / SCROLL REVEAL)
        # ------------------------------------------------
        echo -e "${CYAN} = = > Built-in Mascot:${NC}"
        echo
        archie_play_builtin_cat_scroll 2 0.025 0.30
    fi

    echo
    return 0
}

# =========================
# #MARKER: BUILT-IN CAT SCROLL PLAYER
# =========================
# PURPOSE:
# - Provide A Hardcoded Fallback Mascot When No External ASCII File Exists
# - Use The Same Old-School Line-By-Line Reveal Effect
# - Keep The Body Small / Proportional / Readable
#
# DESIGN:
# - Short Burst Only
# - No Infinite Loop
# - Safe Between-File Intermission Only
# =========================
# =========================
# #MARKER: BUILT-IN CAT (ANIMATED INTERMISSION v2)
# =========================
# PURPOSE:
# - Larger, more expressive fallback mascot
# - Two-frame flip animation (tail wag / body shift)
# - No external file required
#
# DESIGN:
# - Fills more vertical space
# - Clean silhouette (no visual noise)
# - Fast flip = illusion of motion
# =========================
archie_play_builtin_cat_scroll() {
    local passes="${1:-4}"
    local frame_delay="${2:-0.18}"

    local -a frame1=(
""
"              /\\_/\\"
"             / o o \\"
"            (   \"   )"
"             \\~(*)~/"
"              - ^ -"
""
"        /|\\            /|\\"
"       / | \\__________/ | \\"
"      /  |              |  \\"
"         |              |"
"         |              |"
"         |              |"
"         |              |"
"        /                \\"
"       /   /\\      /\\     \\"
"      /___/  \\____/  \\_____\\"
""
"                 ~~~"
    )

    local -a frame2=(
""
"              /\\_/\\"
"             / o o \\"
"            (   \"   )"
"             \\~(*)~/"
"              - ^ -"
""
"        /|\\            /|\\"
"       / | \\__________/ | \\"
"      /  |              |  \\"
"         |              |"
"         |              |"
"         |              |"
"         |              |"
"        /                \\"
"       /   /\\      /\\     \\"
"      /___/  \\____/  \\_____\\"
""
"               ~~~"
    )

    local i
    for (( i=0; i<passes; i++ )); do
        printf "\033[2J\033[H"

        echo -e "${MAGENTA}================================================${NC}"
        echo -e "${MAGENTA}              ARCHIE INTERMISSION               ${NC}"
        echo -e "${MAGENTA}================================================${NC}"
        echo

        printf '%s\n' "${frame1[@]}"
        sleep "$frame_delay"

        printf "\033[2J\033[H"
        echo -e "${MAGENTA}================================================${NC}"
        echo -e "${MAGENTA}              ARCHIE INTERMISSION               ${NC}"
        echo -e "${MAGENTA}================================================${NC}"
        echo

        printf '%s\n' "${frame2[@]}"
        sleep "$frame_delay"
    done

    return 0
}

# =========================
# #MARKER: ASCII SCROLL PLAYER
# =========================
# PURPOSE:
# - Read An ASCII Art File Line-By-Line Very Fast
# - Create A Retro "Screen Reveal" / "Scrolling In" Effect
# - Short Burst Only, Then Return To ARCHIE
# =========================
archie_play_ascii_scroll() {
    local art_file="$1"
    local passes="${2:-2}"
    local line_delay="${3:-0.02}"
    local hold_delay="${4:-0.35}"
    local pass

    [[ -f "$art_file" ]] || return 1

    for (( pass=1; pass<=passes; pass++ )); do
        printf "\033[2J\033[H"

        echo -e "${MAGENTA}================================================${NC}"
        echo -e "${MAGENTA}              ARCHIE INTERMISSION               ${NC}"
        echo -e "${MAGENTA}================================================${NC}"
        echo

        while IFS= read -r line || [[ -n "$line" ]]; do
            printf '%s\n' "$line"
            sleep "$line_delay"
        done < "$art_file"

        echo
        sleep "$hold_delay"
    done

    return 0
}

# -------/\----------- EASTER EGG END ------/\------------

# -----------\/------- HELPERS -----\/-------------
pause() {
    echo -e "${GR}>->->->-> = = > Review Above Carefully.....${NC}"
    echo -e "${BW}>->->->-> = = > Screen Will Clear When You ${NC}"
    echo -e "${YE}>->->->-> = = > Press Enter To Continue....${NC}"
    read -r _
}

is_exit_token() {
    local v="${1:-}"
    [[ "$v" == "0" || "$v" == "0." || "$v" == "q" || "$v" == "Q" ]]
}

ask_yes_no() {
    local prompt="$1"
    local ans

    echo -e "${YELLOW}${prompt}${NC}"
    read -r ans

    ans="${ans,,}"
    ans="${ans//[[:space:]]/}"

    case "${ans:-2}" in
        y|yes|1)
            return 0
            ;;
        n|no|2|"")
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

format_seconds_hms() {
    local total="${1:-0}"
    local h m s

    (( total < 0 )) && total=0

    h=$(( total / 3600 ))
    m=$(( (total % 3600) / 60 ))
    s=$(( total % 60 ))

    if (( h > 0 )); then
        printf '%02dh%02dm%02ds' "$h" "$m" "$s"
    elif (( m > 0 )); then
        printf '%02dm%02ds' "$m" "$s"
    else
        printf '%02ds' "$s"
    fi
}

trim_name() {
    local name="$1"
    local max_len="${2:-32}"

    if (( ${#name} <= max_len )); then
        printf '%s\n' "$name"
    else
        printf '...%s\n' "${name: -$max_len}"
    fi
}

# ========================================================
# #MARKER: SMART FILENAME SHORTEN HELPER
# ========================================================
# PURPOSE:
# - Provide ONE authoritative shortening rule for long filename stems
# - Preserve meaningful front intent when it exists
# - Keep zero-padded camera junk in the old tail-only style
#
# WHY THIS EXISTS:
# - ARCHIE currently had different tail lengths in different places
# - That breaks coherence between:
#     output naming
#     existing-output detection
#     existing-output lookup
#
# RULES:
# - If shortening is disabled:
#     return full stem unchanged
# - If stem is already short enough:
#     return full stem unchanged
# - If the front slice is only zeros:
#     treat it as numeric padding / noise
#     return tail only
# - Otherwise:
#     preserve prefix + "_" + tail
#
# IMPORTANT:
# - We intentionally avoid heavy parsing / tokenization
# - We intentionally keep this simple and fast
# - This helper must be the ONLY place that decides shortened stems
# ========================================================
archie_get_shortened_stem() {
    local stem="$1"
    local keep_prefix="${2:-$ARCHIE_NAME_SHORTEN_KEEP_PREFIX}"
    local keep_tail="${3:-$ARCHIE_NAME_SHORTEN_KEEP_TAIL}"

    local stem_len
    local prefix_part=""
    local tail_part=""

    stem_len="${#stem}"

    # ----------------------------------------------------
    # GLOBAL DISABLE
    # ----------------------------------------------------
    # PURPOSE:
    # - Allow ARCHIE to preserve full human-readable filenames
    #   during runs where shortening is not wanted
    # ----------------------------------------------------
    if (( ARCHIE_NAME_SHORTEN_ENABLE == 0 )); then
        printf '%s\n' "$stem"
        return 0
    fi

    # ----------------------------------------------------
    # SANITY CLAMPS
    # ----------------------------------------------------
    # PURPOSE:
    # - Prevent weird negative / empty slicing behavior
    # - Keep helper predictable even if vars are set badly
    # ----------------------------------------------------
    (( keep_prefix < 0 )) && keep_prefix=0
    (( keep_tail   < 1 )) && keep_tail=1

    # ----------------------------------------------------
    # SHORT STEMS STAY WHOLE
    # ----------------------------------------------------
    # RULE:
    # - If the name already fits inside the requested tail window,
    #   do not mutilate it just because shortening is enabled
    # ----------------------------------------------------
    if (( stem_len <= keep_tail )); then
        printf '%s\n' "$stem"
        return 0
    fi

    tail_part="${stem: -keep_tail}"

    # ----------------------------------------------------
    # OPTIONAL PREFIX PRESERVATION
    # ----------------------------------------------------
    # RULE:
    # - Prefix preservation only matters if user requested it
    # - If prefix length is zero, this becomes classic tail-only mode
    # ----------------------------------------------------
    if (( keep_prefix > 0 )); then
        if (( stem_len <= keep_prefix )); then
            prefix_part="$stem"
        else
            prefix_part="${stem:0:keep_prefix}"
        fi
    fi

    # ----------------------------------------------------
    # ZERO-PADDED FRONT = NOISE
    # ----------------------------------------------------
    # PURPOSE:
    # - Preserve current expected behavior for long camera dump names
    # - If the preserved front slice is only zeros, do NOT keep it
    #
    # EXAMPLES:
    # - 000000000123456789  -> tail only
    # - a1_000000001234567  -> keep a1 + tail
    # ----------------------------------------------------
    if [[ -z "$prefix_part" || "$prefix_part" =~ ^0+$ ]]; then
        printf '%s\n' "$tail_part"
        return 0
    fi

    # ----------------------------------------------------
    # MEANINGFUL PREFIX PRESENT
    # ----------------------------------------------------
    # OUTPUT:
    # - prefix_tail
    #
    # NOTE:
    # - We intentionally keep this simple
    # - No token parsing / delimiter analysis / dedupe tricks here
    # ----------------------------------------------------
    printf '%s_%s\n' "$prefix_part" "$tail_part"
}

run_with_progress() {
    local label="$1"
    shift

    local spin='|/-\'
    local wave=(
        ".    "
        "..   "
        "...  "
        ".... "
        "....."
        " ...."
        "  ..."
        "   .."
        "    ."
    )

    local s=0
    local w=0
    local spin_len=${#spin}
    local wave_len=${#wave[@]}

    local start_ts now_ts elapsed
    local avg_seconds=0
    local eta_seconds=0
    local remaining_files=0
    local avg_human=""
    local eta_human=""
    local progress_note=""

    echo -e "${CYAN} = = > ${label}${NC}" >&2

    start_ts="$(date +%s)"

    "$@" &
    local cmd_pid=$!

    while kill -0 "$cmd_pid" 2>/dev/null; do
        progress_note=""

        # ========================================================
        # ETA DISPLAY POLICY
        # ========================================================
        # SHOW AFTER 3 COMPLETED FILES:
        # - By then we have enough data for a rough clue
        # - Before that, better to avoid fake confidence
        # ========================================================
        if (( ARCHIE_PROGRESS_DONE_COUNT >= 3 && ARCHIE_PROGRESS_TOTAL_FILES > 0 )); then
            avg_seconds=$(( ARCHIE_PROGRESS_TOTAL_SECONDS / ARCHIE_PROGRESS_DONE_COUNT ))
            remaining_files=$(( ARCHIE_PROGRESS_TOTAL_FILES - ARCHIE_PROGRESS_DONE_COUNT ))

            if (( remaining_files < 0 )); then
                remaining_files=0
            fi

            eta_seconds=$(( avg_seconds * remaining_files ))
            avg_human="$(format_seconds_hms "$avg_seconds")"
            eta_human="$(format_seconds_hms "$eta_seconds")"

            progress_note="  ${CYAN}file ${ARCHIE_PROGRESS_CURRENT_INDEX}/${ARCHIE_PROGRESS_TOTAL_FILES}${NC}${YELLOW}  avg ${avg_human}  approx eta ${eta_human}${NC}"
        elif (( ARCHIE_PROGRESS_DONE_COUNT > 0 && ARCHIE_PROGRESS_TOTAL_FILES > 0 )); then
            progress_note="  ${CYAN}file ${ARCHIE_PROGRESS_CURRENT_INDEX}/${ARCHIE_PROGRESS_TOTAL_FILES}${NC}${YELLOW}  gathering timing data...${NC}"
        else
            progress_note="  ${CYAN}file ${ARCHIE_PROGRESS_CURRENT_INDEX}/${ARCHIE_PROGRESS_TOTAL_FILES}${NC}"
        fi

        printf '\r%b' "${YELLOW}   [${spin:s:1}] . . ${wave[w]}-WORKING-${wave[w]} . . [${spin:s:1}]${NC}${progress_note}" >&2

        s=$(( (s + 1) % spin_len ))
        w=$(( (w + 1) % wave_len ))
        sleep 0.20
    done

    wait "$cmd_pid"
    local cmd_status=$?

    now_ts="$(date +%s)"
    elapsed=$(( now_ts - start_ts ))
    (( elapsed < 0 )) && elapsed=0

    ARCHIE_PROGRESS_LAST_ELAPSED="$elapsed"
    ARCHIE_PROGRESS_TOTAL_SECONDS=$(( ARCHIE_PROGRESS_TOTAL_SECONDS + elapsed ))
    ARCHIE_PROGRESS_DONE_COUNT=$(( ARCHIE_PROGRESS_DONE_COUNT + 1 ))

    printf '\r%*s\r' 150 '' >&2
    printf '\n' >&2

    return "$cmd_status"
}

# ========================================================
# #MARKER: EXISTING OUTPUT MATCH CHECK (RESUME SAFETY)
# ========================================================
# PURPOSE:
# - Detect if this source file already has a completed archival output
# - Allow ARCHIE to safely resume after interruption
#
# DESIGN:
# - Match based on:
#     current prefix (level)
#     + source tail (same logic as output naming)
#
# IMPORTANT:
# - We DO NOT rely on sequence number (it may drift)
# - We DO NOT rely on logs or ledger
# - We ONLY skip when a real output file exists
#
# RESULT:
# - Prevents re-encoding already completed work
# - Saves massive time on large interrupted batches
# ========================================================
archie_existing_output_for_source() {
    local prefix="$1"
    local src="$2"
    local base stem short_stem

    base="$(basename "$src")"
    stem="${base%.*}"

    # ----------------------------------------------------
    # IMPORTANT:
    # - Resume-safe matching MUST use the same shortening rule
    #   as output generation
    # - We no longer invent local tail logic here
    # ----------------------------------------------------
    short_stem="$(archie_get_shortened_stem "$stem")"

    # Look for any matching output with this prefix + shortened stem
    compgen -G "${prefix}*_${short_stem}.mkv" > /dev/null 2>&1
}

# ========================================================
# #MARKER: EXISTING OUTPUT PATH LOOKUP (RESUME COHERENCE)
# ========================================================
# PURPOSE:
# - Return the first matching completed archival output path
# - Used when resume-safe skip detects work already done
#
# WHY THIS EXISTS:
# - We want resumed runs to remain truthful in:
#     progress / ETA
#     batch-kept total size
# - So we need the actual existing file path, not just a yes/no match
#
# OUTPUT:
# - Prints matching output path
# - Returns 0 if found
# - Returns 1 if not found
# ========================================================
archie_get_existing_output_for_source() {
    local prefix="$1"
    local src="$2"
    local base stem short_stem
    local -a matches=()

    base="$(basename "$src")"
    stem="${base%.*}"

    # ----------------------------------------------------
    # IMPORTANT:
    # - Existing-output lookup must use the exact same shortened
    #   stem that output generation and match detection use
    # ----------------------------------------------------
    short_stem="$(archie_get_shortened_stem "$stem")"

    shopt -s nullglob
    matches=( "${prefix}"*_"${short_stem}".mkv )
    shopt -u nullglob

    if (( ${#matches[@]} > 0 )); then
        printf '%s\n' "${matches[0]}"
        return 0
    fi

    return 1
}

archie_show_log_tail() {
    local log_file="$1"
    local lines="${2:-20}"

    if [[ ! -f "$log_file" ]]; then
        echo -e "${YELLOW} = = > ffmpeg log was not created:${NC} ${CYAN}$log_file${NC}"
        echo
        return 0
    fi

    echo -e "${YELLOW} = = > Last ${lines} line(s) from:${NC} ${CYAN}$log_file${NC}"
    tail -n "$lines" -- "$log_file" 2>/dev/null || true
    echo

    return 0
}

trim_path_display() {
    local path="$1"
    local max_parts="${2:-3}"

    awk -v p="$path" -v m="$max_parts" 'BEGIN {
        n=split(p, a, "/")
        if (n <= m || p !~ /\//) {
            print p
            exit
        }
        out="..."
        for (i=n-m+1; i<=n; i++) {
            if (a[i] != "") out=out "/" a[i]
        }
        print out
    }'
}

get_folder_size_human() {
    local path="${1:-.}"

    if [[ -e "$path" ]]; then
        du -sh -- "$path" 2>/dev/null | awk '{print $1}'
    else
        printf '%s\n' "N/A"
    fi
}

bytes_to_human() {
    local bytes="${1:-0}"

    awk -v b="$bytes" 'BEGIN {
        split("B KB MB GB TB PB", u, " ")
        i=1
        while (b >= 1024 && i < 6) {
            b /= 1024
            i++
        }

        if (i == 1) {
            printf "%.0f%s", b, u[i]
        } else {
            printf "%.1f%s", b, u[i]
        }
    }'
}

sum_file_sizes() {
    local total=0
    local f size

    for f in "$@"; do
        [[ -f "$f" ]] || continue
        size="$(stat -c%s -- "$f" 2>/dev/null || printf '0')"
        total=$(( total + size ))
    done

    printf '%s\n' "$total"
}

show_space_overview() {
    local cwd cwd_display
    local free total free_color free_gb wd_size meta_size

    cwd="$(pwd)"
    cwd_display="$(trim_path_display "$cwd" 3)"

    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}        SPACE OVERVIEW / WORKING CONTEXT        ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "${GREEN} = = > Working Folder:${NC} ${YELLOW}$cwd_display${NC}"

    free_gb=$(df -BG . | awk 'NR==2 {gsub("G","",$4); print $4}')

    if (( free_gb < 20 )); then
        free_color=$RED
    elif (( free_gb < 50 )); then
        free_color=$YELLOW
    else
        free_color=$GREEN
    fi

    read -r free total <<< "$(df -h . | awk 'NR==2 {print $4, $2}')"
    echo -e "${free_color} = = > $free${NC} ${YELLOW}<-- Total${NC}"
    echo -e "${free_color} = = >  ^ Free Space${NC}"

    wd_size="$(get_folder_size_human .)"
    meta_size="$(get_folder_size_human "$ARCHIE_META_DIR")"
    echo -e "${CYAN} = = > Working Dir Size:${NC} ${YELLOW}$wd_size${NC}"
    echo -e "${CYAN} = = > ARCHIE_META Size:${NC} ${YELLOW}$meta_size${NC}"
    echo
}

# ------------------ DISCOVERY / LISTING ------------------
archie_collect_targets() {
    shopt -s nullglob nocaseglob
    local -a vids=(*.{LRV,mkv,mp4,avi,mov,mpg,mpeg,ts,m4v,ogv,flv,3gp,divx,webm,wmv,xvid})
    shopt -u nullglob nocaseglob

    local f
    for f in "${vids[@]}"; do
        [[ -f "$f" ]] || continue
        [[ "$f" =~ ^(ARCHIVE_L1_|ARCHIVE_L2_|ARCHIVE_L3_|ARCHIVE_L4_|PILOT_ARCHIVE_|REKEY_|SUTURED_|BARFIX_|SUBPACKED_|OEM_|PILOT_SUTURED_) ]] && continue
        printf '%s\n' "$f"
    done
}

archie_print_targets() {
    local title="$1"
    shift
    local items=("$@")

    echo -e "${CYAN} = = > ${title}:${NC} ${YELLOW}${#items[@]}${NC}"
    if ((${#items[@]} > 0)); then
        printf "${CYAN}   - ${NC}%s\n" "${items[@]}"
    fi
    echo
}

archie_make_output_name() {
    local prefix="$1"
    local seq="$2"
    local src="$3"
    local base stem short_stem seq_pad

    base="$(basename "$src")"
    stem="${base%.*}"

    # ----------------------------------------------------
    # IMPORTANT:
    # - Output generation now uses the same shared shortening helper
    #   as resume detection / lookup
    # - This keeps ARCHIE naming and resume behavior unified
    # ----------------------------------------------------
    short_stem="$(archie_get_shortened_stem "$stem")"

    printf -v seq_pad "%0${ARCHIE_SEQUENCE_PAD}d" "$seq"
    printf '%s%s_%s.mkv\n' "$prefix" "$seq_pad" "$short_stem"
}

archie_limit_targets_interactive() {
    local -n _targets_ref=$1
    local mode how_many total

    total="${#_targets_ref[@]}"
    (( total == 0 )) && return 0

    echo -e "${CYAN} = = > Targets Found:${NC} ${YELLOW}$total${NC}"
    echo -e "${CYAN} = = > Batch Limit Mode:${NC}"
    echo -e "${CYAN}     1) Use Full Batch${NC}"
    echo -e "${CYAN}     2) Limit To First N Files${NC}"
    echo -e "${CYAN}     0.) Return / Cancel${NC}"
    echo

    echo -e "${YELLOW} = = > Select option [1-2 | 0.=cancel] (Default: Full Batch): ${NC}"
    read -r mode
    mode="${mode//[[:space:]]/}"

    if is_exit_token "$mode" || [[ "$mode" == "0" ]]; then
        return 1
    fi

    case "$mode" in
        1)
            echo -e "${GREEN} = = > Using Full Batch:${NC} ${YELLOW}${#_targets_ref[@]}${NC} file(s)"
            echo
            return 0
            ;;
        2)
            echo -e "${YELLOW} = = > Enter How Many Files To Process:${NC}"
            read -r how_many
            how_many="${how_many//[[:space:]]/}"

            if is_exit_token "$how_many" || [[ "$how_many" == "0" ]]; then
                return 1
            fi

            if [[ "$how_many" =~ ^[0-9]+$ ]] && (( how_many > 0 )); then
                if (( how_many < total )); then
                    _targets_ref=("${_targets_ref[@]:0:how_many}")
                fi
                echo -e "${GREEN} = = > Batch Limited To:${NC} ${YELLOW}${#_targets_ref[@]}${NC} file(s)"
                echo
                return 0
            fi
            echo -e "${YELLOW} = = > Invalid Count. Using Full Batch Instead.${NC}"
            echo
            return 0
            ;;
        *)
            echo -e "${YELLOW} = = > Invalid Selection. Using Full Batch Instead.${NC}"
            echo
            return 0
            ;;
    esac
}

# ------------------ METADATA / LEDGER HELPERS ------------------
archie_ensure_meta_dir() {
    mkdir -p -- "$ARCHIE_META_DIR"
}

archie_ensure_ledger() {
    if [[ ! -f "$ARCHIE_LEDGER" ]]; then
        printf '%s\n' \
            "source_file,output_file,level,audio_mode,metadata_mode,orig_size,new_size,delta_percent,source_sha256,processed_utc,metadata_sidecar,ffmpeg_log" \
            > "$ARCHIE_LEDGER"
    fi
}

safe_stem() {
    local name="$1"
    name="${name##*/}"
    name="${name%.*}"
    name="${name// /_}"
    name="${name//[^A-Za-z0-9._-]/_}"
    printf '%s\n' "$name"
}

archie_capture_metadata_sidecar() {
    local src="$1"
    local stem meta_json meta_txt sha_file

    archie_ensure_meta_dir
    stem="$(safe_stem "$src")"

    meta_json="$ARCHIE_META_DIR/${stem}.ffprobe.json"
    meta_txt="$ARCHIE_META_DIR/${stem}.stat.txt"
    sha_file="$ARCHIE_META_DIR/${stem}.sha256.txt"

    if have_cmd ffprobe; then
        ffprobe -v quiet -print_format json -show_format -show_streams "$src" > "$meta_json" 2>/dev/null || true
    fi

    {
        echo "SOURCE_FILE=$src"
        echo "CAPTURED_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        stat --printf='SIZE=%s\nMTIME_EPOCH=%Y\nATIME_EPOCH=%X\nCTIME_EPOCH=%Z\nMODE=%a\nUID=%u\nGID=%g\n' -- "$src" 2>/dev/null || true
    } > "$meta_txt"

    if have_cmd sha256sum; then
        sha256sum -- "$src" > "$sha_file" 2>/dev/null || true
    fi

    printf '%s\n' "$meta_json"
}

percent_change() {
    local orig_size="$1"
    local new_size="$2"

    awk -v o="$orig_size" -v n="$new_size" 'BEGIN {
        if (o <= 0) print 0;
        else printf "%.0f", ((n - o) / o) * 100
    }'
}

archie_append_ledger_row() {
    local src="$1"
    local out="$2"
    local level="$3"
    local audio_mode="$4"
    local metadata_mode="$5"
    local orig_size="$6"
    local new_size="$7"
    local delta_percent="$8"
    local metadata_sidecar="$9"
    local ffmpeg_log="${10}"
    local sha256_value processed_utc

    processed_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sha256_value=""

    if have_cmd sha256sum && [[ -f "$src" ]]; then
        sha256_value="$(sha256sum -- "$src" 2>/dev/null | awk '{print $1}')"
    fi

    archie_ensure_ledger
    printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
        "$src" "$out" "$level" "$audio_mode" "$metadata_mode" \
        "$orig_size" "$new_size" "$delta_percent" "$sha256_value" "$processed_utc" "$metadata_sidecar" "$ffmpeg_log" \
        >> "$ARCHIE_LEDGER"
}

size_gate_passes() {
    local orig_size="$1"
    local new_size="$2"
    local tolerance_percent="${3:-$ARCHIE_SIZE_TOLERANCE_PERCENT}"
    local allowed_max

    if (( tolerance_percent <= 0 )); then
        (( new_size < orig_size ))
        return
    fi

    allowed_max=$(awk -v o="$orig_size" -v t="$tolerance_percent" 'BEGIN { printf "%.0f", o * (1 + t/100) }')
    (( new_size <= allowed_max ))
}

# ------------------ AUDIO / ENCODE SETTINGS ------------------
archie_get_prefix_for_level() {
    case "$1" in
        1) printf '%s\n' "ARCHIVE_L1_" ;;
        2) printf '%s\n' "ARCHIVE_L2_" ;;
        3) printf '%s\n' "ARCHIVE_L3_" ;;
        4) printf '%s\n' "ARCHIVE_L4_" ;;
        *) printf '%s\n' "ARCHIVE_L2_" ;;
    esac
}

archie_pick_audio_mode() {
    local mode
    archie_play_builtin_cat_scroll
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}              ARCHIE AUDIO POLICY               ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo
    echo -e "${CYAN} = = > Audio Modes:${NC}"
    echo -e "${CYAN}     1) copy   = Keep source audio as-is${NC}"
    echo -e "${CYAN}     2) aac    = Re-encode audio to AAC${NC}"
    echo -e "${CYAN}     3) strip  = Remove audio entirely${NC}"
    echo
    echo -e "${CYAN} = = > 1) Keep Audio 2) Audio to AAC 3) Remove Audio Entirely ${NC}"
    echo
    echo -e "${YELLOW} = = > Choose Audio Mode [1-3 | 0.=cancel | q] (Default: ${GREEN}${ARCHIE_DEFAULT_AUDIO_MODE}${YELLOW}): ${NC}"
    read -r mode
    mode="${mode//[[:space:]]/}"

    if is_exit_token "$mode"; then
        return 1
    fi

    case "${mode:-2}" in
        1) ARCHIE_SELECTED_AUDIO_MODE="copy" ;;
        2) ARCHIE_SELECTED_AUDIO_MODE="aac" ;;
        3) ARCHIE_SELECTED_AUDIO_MODE="strip" ;;
        *) ARCHIE_SELECTED_AUDIO_MODE="$ARCHIE_DEFAULT_AUDIO_MODE" ;;
    esac

    return 0
}

archie_pick_metadata_mode() {
    local mode
    archie_play_builtin_cat_scroll
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}            ARCHIE METADATA POLICY              ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo
    echo -e "${CYAN} = = > Metadata Modes:${NC}"
    echo -e "${CYAN}     1) Sidecar_Strip = Save metadata for us, strip output metadata${NC}"
    echo -e "${CYAN}     2) Restore_Common = Save sidecars, keep common tags on output${NC}"
    echo -e "${CYAN}     3) Minimal_Skip  = Skip metadata capture${NC}"
    echo
    echo -e "${CYAN} = = > 1) Sidecar_Strip 2) Restore_Common 3) Minimal_Skip ${NC}"
    echo
    echo -e "${YELLOW} = = > Choose Metadata Mode [1-3 | 0.=cancel | q] (Default: ${GREEN}${ARCHIE_DEFAULT_METADATA_MODE}${YELLOW}): ${NC}"
    read -r mode
    mode="${mode//[[:space:]]/}"

    if is_exit_token "$mode"; then
        return 1
    fi

    case "${mode:-1}" in
        1) ARCHIE_SELECTED_METADATA_MODE="sidecar_strip" ;;
        2) ARCHIE_SELECTED_METADATA_MODE="restore_common" ;;
        3) ARCHIE_SELECTED_METADATA_MODE="minimal_skip" ;;
        *) ARCHIE_SELECTED_METADATA_MODE="$ARCHIE_DEFAULT_METADATA_MODE" ;;
    esac

    return 0
}

# ========================================================
# #MARKER: CUT-FRIENDLY / PRE-FACTORY PICKER
# ========================================================
# PURPOSE:
# - Let user decide whether this ARCHIE run should also target
#   factory-friendlier keyframe spacing
#
# IMPORTANT:
# - This does NOT replace L1 / L2 / L3 / L4
# - It layers ON TOP of the selected archival level
# - So every level remains available in either mode:
#     normal
#     cut-friendly
#
# WHY THIS EXISTS:
# - Standard ARCHIE archival work focuses on shrink efficiency
# - FACTORY-prep work benefits from tighter / more predictable GOPs
# - Keeping this as a separate toggle avoids muddying level meaning
# ========================================================
archie_pick_cut_friendly_mode() {
    local mode

    archie_play_builtin_cat_scroll
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}        ARCHIE CUT-FRIENDLY / PRE-FACTORY       ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo
    echo -e "${CYAN} = = > Encode Modes:${NC}"
    echo -e "${CYAN}     1) Off = Standard ARCHIE archival behavior${NC}"
    echo -e "${CYAN}     2) On  = Target ~1-second keyframe spacing${NC}"
    echo
    echo -e "${CYAN} = = > NOTES:${NC}"
    echo -e "${CYAN}     - This mode is independent of L1 / L2 / L3 / L4${NC}"
    echo -e "${CYAN}     - It may help FACTORY skip unnecessary REKEY work${NC}"
    echo -e "${CYAN}     - It may also make outputs a bit less compression-efficient${NC}"
    echo
    echo -e "${YELLOW} = = > Choose Cut-Friendly Mode [1-2 | 0.=cancel | q] (Default: ${GREEN}${ARCHIE_DEFAULT_CUT_FRIENDLY_MODE}${YELLOW}): ${NC}"
    read -r mode
    mode="${mode//[[:space:]]/}"

    if is_exit_token "$mode"; then
        return 1
    fi

    case "$mode" in
        2)
            ARCHIE_SELECTED_CUT_FRIENDLY_MODE="on"
            ;;
        1|"")
            ARCHIE_SELECTED_CUT_FRIENDLY_MODE="off"
            ;;
        *)
            ARCHIE_SELECTED_CUT_FRIENDLY_MODE="$ARCHIE_DEFAULT_CUT_FRIENDLY_MODE"
            ;;
    esac

    return 0
}

archie_encode_one_file() {
    local level="$1"
    local audio_mode="$2"
    local metadata_mode="$3"
    local cut_friendly_mode="$4"
    local in="$5"
    local out="$6"
    local log_file="$7"

    local v_preset v_crf audio_bitrate
    local fps_raw fps_int
    local -a meta_args=()
    local -a gop_args=()

    case "$level" in
        1)
            v_preset="slow"
            v_crf="21"
            audio_bitrate="192k"
            ;;
        2)
            v_preset="medium"
            v_crf="25"
            audio_bitrate="128k"
            ;;
        3)
            v_preset="medium"
            v_crf="29"
            audio_bitrate="96k"
            ;;
        4)
            v_preset="slow"
            v_crf="32"
            audio_bitrate="96k"
            ;;
        *)
            return 1
            ;;
    esac

    case "$metadata_mode" in
        sidecar_strip)
            meta_args=(-map_metadata -1 -map_chapters -1)
            ;;
        restore_common)
            meta_args=(-map_metadata 0 -map_chapters -1)
            ;;
        minimal_skip)
            meta_args=()
            ;;
        *)
            meta_args=(-map_metadata -1 -map_chapters -1)
            ;;
    esac

    # ----------------------------------------------------
    # OPTIONAL CUT-FRIENDLY GOP / KEYFRAME TARGETING
    # ----------------------------------------------------
    # PURPOSE:
    # - Try to produce ~1-second keyframe spacing so downstream
    #   cut operations are more likely to be friendly first try
    #
    # DESIGN:
    # - We derive GOP target from source fps when possible
    # - We clamp to sane integer values for x264 / ffmpeg args
    # - Scene-cut remains allowed, but max GOP is kept tight
    #
    # IMPORTANT:
    # - This mode does NOT guarantee FACTORY will always skip REKEY
    # - FACTORY should still judge suitability normally
    # ----------------------------------------------------
    if [[ "$cut_friendly_mode" == "on" ]]; then
        fps_raw="$(ffprobe -v error \
            -select_streams v:0 \
            -show_entries stream=avg_frame_rate \
            -of default=noprint_wrappers=1:nokey=1 \
            "$in" 2>/dev/null || true)"

        fps_int="$(awk -v r="$fps_raw" 'BEGIN {
            n=split(r, a, "/")
            if (n == 2 && a[2] > 0) {
                fps=a[1]/a[2]
            } else if (r ~ /^[0-9]+([.][0-9]+)?$/) {
                fps=r+0
            } else {
                fps=0
            }

            if (fps < 1) {
                print 24
                exit
            }

            g=int(fps + 0.5)

            if (g < 1)   g=1
            if (g > 240) g=240

            print g
        }')"

        gop_args=(
            -g "$fps_int"
            -keyint_min "$fps_int"
            -sc_threshold 40
            -x264-params "open-gop=0:min-keyint=${fps_int}:keyint=${fps_int}"
        )
    fi

    {
        echo "ARCHIE_DEBUG|entered_encode_helper=1"
        echo "ARCHIE_DEBUG|input=$in"
        echo "ARCHIE_DEBUG|output=$out"
        echo "ARCHIE_DEBUG|level=$level|audio_mode=$audio_mode|metadata_mode=$metadata_mode|cut_friendly_mode=$cut_friendly_mode"
        if [[ "$cut_friendly_mode" == "on" ]]; then
            echo "ARCHIE_DEBUG|gop_target_frames=$fps_int"
            echo "ARCHIE_DEBUG|source_avg_frame_rate=${fps_raw:-unknown}"
        fi
        echo "ARCHIE_DEBUG|utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } >> "$log_file"

    case "$audio_mode" in
        strip)
            ffmpeg -y -hide_banner -loglevel warning -stats -i "$in" \
                -map '0:v:0' \
                "${meta_args[@]}" \
                -sn -dn \
                -c:v libx264 -preset "$v_preset" -crf "$v_crf" \
                "${gop_args[@]}" \
                -an \
                "$out" \
                >> "$log_file" 2>&1
            ;;
        aac)
            ffmpeg -y -hide_banner -loglevel warning -stats -i "$in" \
                -map '0:v:0' -map '0:a?' \
                "${meta_args[@]}" \
                -sn -dn \
                -c:v libx264 -preset "$v_preset" -crf "$v_crf" \
                "${gop_args[@]}" \
                -c:a aac -b:a "$audio_bitrate" \
                "$out" \
                >> "$log_file" 2>&1
            ;;
        copy)
            ffmpeg -y -hide_banner -loglevel warning -stats -i "$in" \
                -map '0:v:0' -map '0:a?' \
                "${meta_args[@]}" \
                -sn -dn \
                -c:v libx264 -preset "$v_preset" -crf "$v_crf" \
                "${gop_args[@]}" \
                -c:a copy \
                "$out" \
                >> "$log_file" 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

archie_build_tarball() {
    local tar_name="$1"
    shift
    local files=("$@")

    # ========================================================
    # ARCHIE TARBALL BUILDER
    # ========================================================
    # PURPOSE:
    # - Bundle ONLY the surviving archival outputs into one tarball
    # - Leave source files, sidecars, logs, and ledger untouched
    #
    # DESIGN RULE:
    # - This is a plain tar container step, not a recompression step
    # - We are packaging already-produced archival outputs
    #
    # IMPORTANT:
    # - If no surviving outputs exist, do NOT build an empty tarball
    # - Caller already decides whether user said yes/no to tar step
    # ========================================================

    if [[ "${#files[@]}" -eq 0 ]]; then
        echo -e "${YE} = = > No New Archival Outputs Were Kept. Tarball Step Skipped.${NC}"
        return 1
    fi

    echo -e "${CYAN} = = > Tarball Target:${NC} ${GREEN}$tar_name${NC}"
    echo -e "${CYAN} = = > Files Going Into Tarball:${NC} ${YELLOW}${#files[@]}${NC}"
    echo

    if run_with_progress "Building Archival Tarball: $(basename "$tar_name")" tar -cf "$tar_name" "${files[@]}"; then
        echo -e "${GR} = = > Tarball Build Completed:${NC} ${CYAN}$tar_name${NC}"
        return 0
    fi

    echo -e "${REB} = = > Tarball Build Failed:${NC} ${CYAN}$tar_name${NC}"
    return 1
}

archie_show_danger_banner() {
    echo -e "${REB}================================================${NC}"
    echo -e "${REB}        ARCHIE WARNING :: DESTRUCTIVE STEP      ${NC}"
    echo -e "${REB}================================================${NC}"
    echo -e "${YELLOW} = = > Original Files May Be Removed.${NC}"
    echo -e "${YELLOW} = = > Metadata Sidecars Are For INTERNAL RECORDS.${NC}"
    echo -e "${YELLOW} = = > Archive Outputs May Be The Only Surviving Media Copies.${NC}"
    echo -e "${REB}================================================${NC}"
    echo
}

# ------------------ MAIN WORKFLOW ------------------
run_archie() {
    local level prefix tar_name audio_mode metadata_mode cut_friendly_mode
    local metadata_sidecar delta_percent batch_delta_percent
    local orig_size new_size
    local batch_source_total_bytes=0
    local batch_kept_total_bytes=0
    local batch_saved_bytes=0
    local -a targets=()
    local -a outputs=()
    local -a source_output_pairs=()
    local f out pair src_from_pair out_from_pair log_file progress_label existing_out existing_size
    local success_count=0
    local fail_count=0
    local no_gain_count=0
    local delete_success_count=0

    clear
    show_space_overview

    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}              ARCHIE.SH  v${ARCHIE_VERSION}                  ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo
    echo -e "${YELLOW} = = > PURPOSE: Re-encode directory-local videos into smaller archival copies.${NC}"
    echo -e "${YELLOW} = = > Originals remain untouched unless you explicitly delete them later.${NC}"
    echo -e "${YELLOW} = = > Outputs that fail to shrink will be discarded automatically.${NC}"
    echo -e "${YELLOW} = = > Metadata is preserved for us in sidecars and stripped from outputs by default.${NC}"
    echo -e "${YELLOW} = = > Double Check Digits From Ext If You Want To Keep Front Of Long Filenames.${NC}"
    echo
    echo -e "${CYAN} = = > Archival Levels:${NC}"
    echo -e "${CYAN}     1) Light Shrink   (Higher Quality / Larger Files)${NC}"
    echo -e "${CYAN}     2) Balanced       (Good Archive Default)${NC}"
    echo -e "${CYAN}     3) Aggressive     (Storage First / Smaller Files)${NC}"
    echo -e "${CYAN}     4) Brute Force    (Shrinkage Priority / Hard Squeeze)${NC}"
    echo

    mapfile -t targets < <(archie_collect_targets)

    if ! archie_limit_targets_interactive targets; then
        echo -e "${YELLOW} = = > Archival Batch Selection Cancelled.${NC}"
        echo
        pause
        return 0
    fi

    if ((${#targets[@]} == 0)); then
        echo -e "${YELLOW} = = > No Eligible Source Videos Found In Current Folder.${NC}"
        echo
        pause
        return 0
    fi

    # ========================================================
    # BATCH SIZE BASELINE
    # ========================================================
    batch_source_total_bytes="$(sum_file_sizes "${targets[@]}")"

    # ========================================================
    # RESET / ARM ROLLING ETA STATE FOR THIS RUN
    # ========================================================
    ARCHIE_PROGRESS_DONE_COUNT=0
    ARCHIE_PROGRESS_TOTAL_SECONDS=0
    ARCHIE_PROGRESS_TOTAL_FILES="${#targets[@]}"
    ARCHIE_PROGRESS_CURRENT_INDEX=0
    ARCHIE_PROGRESS_LAST_ELAPSED=0

    archie_print_targets "Eligible Archival Targets" "${targets[@]}"

    echo -e "${YELLOW} = = > Select Archival Level [1/2/3/4] (Default: ${ARCHIE_DEFAULT_LEVEL}): ${NC}"
    read -r level
    level="${level:-$ARCHIE_DEFAULT_LEVEL}"
    level="${level//[[:space:]]/}"

    if is_exit_token "$level"; then
        return 0
    fi

    case "$level" in
        1|2|3|4)
            ;;
        *)
            echo -e "${REB} = = > Invalid Archival Level.${NC}"
            pause
            return 1
            ;;
    esac

    if ! archie_pick_audio_mode; then
        echo -e "${YELLOW} = = > Audio Policy Selection Cancelled.${NC}"
        echo
        pause
        return 0
    fi
    audio_mode="$ARCHIE_SELECTED_AUDIO_MODE"

    if ! archie_pick_metadata_mode; then
        echo -e "${YELLOW} = = > Metadata Policy Selection Cancelled.${NC}"
        echo
        pause
        return 0
    fi
    metadata_mode="$ARCHIE_SELECTED_METADATA_MODE"
    if ! archie_pick_cut_friendly_mode; then
        echo -e "${YELLOW} = = > Cut-Friendly / Pre-Factory Selection Cancelled.${NC}"
        echo
        pause
        return 0
    fi
    cut_friendly_mode="$ARCHIE_SELECTED_CUT_FRIENDLY_MODE"

    echo -e "${CYAN} = = > Size Gate Tolerance:${NC}"
    echo -e "${CYAN}     0 = Strict (must be smaller)${NC}"
    echo -e "${CYAN}     N = Allow up to ${GREEN}${ARCHIE_SIZE_TOLERANCE_PERCENT}%${NC}${CYAN} Larger (container overhead forgiveness)${NC}"
    echo

    echo -e "${YELLOW} = = > Enter Tolerance Percent [0-5 recommended | Enter=default] (Default: ${GREEN}${ARCHIE_SIZE_TOLERANCE_PERCENT}%${YELLOW}): ${NC}"
    read -r tol_input
    tol_input="${tol_input//[[:space:]]/}"

    if [[ -n "$tol_input" && "$tol_input" =~ ^[0-9]+$ ]]; then
        ARCHIE_SIZE_TOLERANCE_PERCENT="$tol_input"
    fi

    echo -e "${CYAN} = = > Active Size Tolerance:${NC} ${GREEN}${ARCHIE_SIZE_TOLERANCE_PERCENT}%${NC}"
    echo

    archie_twist_configure

    echo -e "${CYAN} = = > Smart Filename Shortening:${NC}"
    echo -e "${CYAN}     1) Enabled  = Preserve Meaningful Prefix + Tail${NC}"
    echo -e "${CYAN}     2) Disabled = Keep Full Filename Stem${NC}"
    echo

    echo -e "${YELLOW} = = > Select [1-2 | Enter=enabled] (Default: enabled): ${NC}"
    read -r shorten_mode
    shorten_mode="${shorten_mode//[[:space:]]/}"

    case "${shorten_mode:-1}" in
        2)
            ARCHIE_NAME_SHORTEN_ENABLE=0
            ;;
        *)
            ARCHIE_NAME_SHORTEN_ENABLE=1
            ;;
    esac

    if (( ARCHIE_NAME_SHORTEN_ENABLE == 1 )); then
        echo
        echo -e "${CYAN} = = > Prefix Characters To Preserve When Meaningful:${NC}"
        echo -e "${CYAN}     Current Default:${NC} ${GREEN}${ARCHIE_NAME_SHORTEN_KEEP_PREFIX}${NC}"
        echo
        echo -e "${YELLOW} = = > Enter Prefix Keep Length [0-8 recommended | Enter=default]: ${NC}"
        read -r prefix_keep_input
        prefix_keep_input="${prefix_keep_input//[[:space:]]/}"

        if [[ -n "$prefix_keep_input" && "$prefix_keep_input" =~ ^[0-9]+$ ]]; then
            ARCHIE_NAME_SHORTEN_KEEP_PREFIX="$prefix_keep_input"
        fi

        echo
        echo -e "${CYAN} = = > Tail Characters To Preserve:${NC}"
        echo -e "${CYAN}     Current Default:${NC} ${GREEN}${ARCHIE_NAME_SHORTEN_KEEP_TAIL}${NC}"
        echo -e "${CYAN}     Large Values Can Make Shortening Effectively Disappear${NC}"
        echo
        echo -e "${YELLOW} = = > Enter Tail Keep Length [12 recommended | 99=nearly off for many names | Enter=default]: ${NC}"
        read -r tail_keep_input
        tail_keep_input="${tail_keep_input//[[:space:]]/}"

        if [[ -n "$tail_keep_input" && "$tail_keep_input" =~ ^[0-9]+$ ]]; then
            ARCHIE_NAME_SHORTEN_KEEP_TAIL="$tail_keep_input"
        fi
    fi

    prefix="$(archie_get_prefix_for_level "$level")"

    echo
    echo -e "${CYAN} = = > Selected Prefix:${NC} ${GREEN}$prefix${NC}"
    echo -e "${CYAN} = = > Selected Audio Policy:${NC} ${GREEN}$audio_mode${NC}"
    echo -e "${CYAN} = = > Selected Metadata Policy:${NC} ${GREEN}$metadata_mode${NC}"
    echo -e "${CYAN} = = > Selected Cut-Friendly Mode:${NC} ${GREEN}$cut_friendly_mode${NC}"

    if (( ARCHIE_NAME_SHORTEN_ENABLE == 1 )); then
        echo -e "${CYAN} = = > Filename Shortening:${NC} ${GREEN}enabled${NC}"
        echo -e "${CYAN} = = > Meaningful Prefix Keep:${NC} ${YELLOW}${ARCHIE_NAME_SHORTEN_KEEP_PREFIX}${NC}"
        echo -e "${CYAN} = = > Tail Keep:${NC} ${YELLOW}${ARCHIE_NAME_SHORTEN_KEEP_TAIL}${NC}"
    else
        echo -e "${CYAN} = = > Filename Shortening:${NC} ${YELLOW}disabled${NC}"
    fi
    echo

    if ! ask_yes_no " = = > Proceed With Archival Re-Encode Pass? (y/n or 1/2): "; then
        echo -e "${YELLOW} = = > Archival Pass Canceled.${NC}"
        echo
        pause
        return 0
    fi

    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}             ARCHIVAL ENCODE PASS               ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo

    for f in "${targets[@]}"; do
        if archie_existing_output_for_source "$prefix" "$f"; then
            existing_out="$(archie_get_existing_output_for_source "$prefix" "$f" 2>/dev/null || true)"

            echo -e "${YE} = = > [SKIP EXISTING]${NC} ${GREEN}$f${NC}"

            if [[ -n "${existing_out:-}" && -f "$existing_out" ]]; then
                existing_size="$(stat -c%s -- "$existing_out" 2>/dev/null || printf '0')"
                batch_kept_total_bytes=$(( batch_kept_total_bytes + existing_size ))
                echo -e "${CYAN} = = > Existing Output:${NC} ${GREEN}$existing_out${NC}"
                echo -e "${CYAN} = = > Existing Output Size:${NC} ${YELLOW}$existing_size${NC} bytes"
            fi

            ((success_count+=1)) || :
            ARCHIE_PROGRESS_DONE_COUNT=$(( ARCHIE_PROGRESS_DONE_COUNT + 1 ))

            if (( ARCHIE_TWIST_ENABLE == 1 )); then
                if (( ARCHIE_PROGRESS_DONE_COUNT > 0 )) && \
                   (( ARCHIE_PROGRESS_DONE_COUNT % ARCHIE_TWIST_EVERY_N_FILES == 0 )); then
                    archie_twist_cycle
                fi
            fi

            echo
            continue
        fi

        ARCHIE_PROGRESS_CURRENT_INDEX=$(( success_count + fail_count + no_gain_count + 1 ))
        out="$(archie_make_output_name "$prefix" "$((success_count + fail_count + no_gain_count + 1))" "$f")"

        echo -e "${CYAN} = = > Archiving:${NC} ${GREEN}$f${NC}"
        echo -e "${CYAN} = = > Output Name:${NC} ${GREEN}$out${NC}"
        echo -e "${CYAN} = = > Audio Policy:${NC} ${YELLOW}$audio_mode${NC}"
        echo -e "${CYAN} = = > Metadata Policy:${NC} ${YELLOW}$metadata_mode${NC}"

        metadata_sidecar=""
        if [[ "$metadata_mode" != "minimal_skip" ]]; then
            echo -e "${CYAN} = = > Capturing Metadata Sidecar:${NC} ${GREEN}$f${NC}"
            metadata_sidecar="$(archie_capture_metadata_sidecar "$f")"
        fi

        archie_ensure_meta_dir
        log_file="$ARCHIE_META_DIR/$(safe_stem "$f").ffmpeg.log"
        : > "$log_file"

        echo -e "${CYAN} = = > ffmpeg Log:${NC} ${GREEN}$log_file${NC}"

        progress_label="Archival Array: $(trim_name "$(basename "$f")")"

        if run_with_progress "$progress_label" archie_encode_one_file "$level" "$audio_mode" "$metadata_mode" "$cut_friendly_mode" "$f" "$out" "$log_file"; then
            if [[ ! -f "$out" ]]; then
                echo -e "${REB} = = > Encode Reported Success But No Output File Was Found:${NC} ${GREEN}$out${NC}"
                echo -e "${CYAN} = = > Elapsed This File:${NC} ${YELLOW}$(format_seconds_hms "$ARCHIE_PROGRESS_LAST_ELAPSED")${NC}"
                archie_show_log_tail "$log_file" 40 || true
                ((fail_count+=1)) || :
                continue
            fi

            orig_size=$(stat -c%s "$f")
            new_size=$(stat -c%s "$out")

            if ! size_gate_passes "$orig_size" "$new_size" "$ARCHIE_SIZE_TOLERANCE_PERCENT"; then
                echo -e "${YELLOW} = = > No Size Gain. Removing Archival Copy:${NC} ${CYAN}$out${NC}"
                echo -e "${YELLOW} = = > Original Size:${NC} ${YELLOW}$orig_size${NC} bytes"
                echo -e "${YELLOW} = = > New Size:${NC} ${YELLOW}$new_size${NC} bytes"
                echo -e "${CYAN} = = > Elapsed This File:${NC} ${YELLOW}$(format_seconds_hms "$ARCHIE_PROGRESS_LAST_ELAPSED")${NC}"
                rm -f -- "$out"
                ((no_gain_count+=1)) || :
            else
                delta_percent="$(percent_change "$orig_size" "$new_size")"
                echo -e "${GR} = = > Created:${NC} ${CYAN}$out${NC}"
                echo -e "${CYAN} = = > Size Reduced From:${NC} ${YELLOW}$(bytes_to_human "$orig_size")${NC} ${CYAN}to${NC} ${YELLOW}$(bytes_to_human "$new_size")${NC}"
                echo -e "${CYAN} = = > Percent Change:${NC} ${YELLOW}${delta_percent}%${NC}"
                echo -e "${CYAN} = = > Elapsed This File:${NC} ${YELLOW}$(format_seconds_hms "$ARCHIE_PROGRESS_LAST_ELAPSED")${NC}"
                outputs+=("$out")
                source_output_pairs+=("$f|$out")
                batch_kept_total_bytes=$(( batch_kept_total_bytes + new_size ))

                # ========================================================
                # LEDGER WRITE FOR ALL SURVIVING OUTPUTS
                # ========================================================
                # PURPOSE:
                # - Keep ARCHIE_LEDGER as the authoritative record of what
                #   survived the archival gate, regardless of metadata mode
                #
                # RULE:
                # - minimal_skip means:
                #     "do not capture sidecar files"
                #   NOT:
                #     "pretend this archival event never happened"
                #
                # NOTE:
                # - metadata_sidecar will simply be blank when minimal_skip
                #   was selected, and that is fine / intentional
                # ========================================================
                archie_append_ledger_row \
                    "$f" "$out" "$level" "$audio_mode" "$metadata_mode" \
                    "$orig_size" "$new_size" "$delta_percent" "$metadata_sidecar" "$log_file"

                ((success_count+=1)) || :
            fi
        else
            echo -e "${REB} = = > Failed:${NC} ${GREEN}$f${NC}"
            echo -e "${CYAN} = = > Elapsed This File:${NC} ${YELLOW}$(format_seconds_hms "$ARCHIE_PROGRESS_LAST_ELAPSED")${NC}"
            archie_show_log_tail "$log_file" 40 || true
            ((fail_count+=1)) || :
        fi

        if (( ARCHIE_TWIST_ENABLE == 1 )); then
            if (( ARCHIE_PROGRESS_DONE_COUNT > 0 )) && \
               (( ARCHIE_PROGRESS_DONE_COUNT % ARCHIE_TWIST_EVERY_N_FILES == 0 )); then
                archie_twist_cycle
            fi
        fi

        archie_show_easter_egg
        echo
    done

    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}              ARCHIVAL ENCODE SUMMARY           ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "${GREEN} = = > Successful Outputs Kept:${NC} ${YELLOW}$success_count${NC}"
    echo -e "${YELLOW} = = > No-Gain Outputs Removed:${NC} ${YELLOW}$no_gain_count${NC}"

    batch_saved_bytes=$(( batch_source_total_bytes - batch_kept_total_bytes ))
    batch_delta_percent="$(percent_change "$batch_source_total_bytes" "$batch_kept_total_bytes")"

    echo -e "${CYAN} = = > Source Batch Total:${NC} ${YELLOW}$(bytes_to_human "$batch_source_total_bytes")${NC}"
    echo -e "${CYAN} = = > Kept Archive Total:${NC} ${YELLOW}$(bytes_to_human "$batch_kept_total_bytes")${NC}"

    if (( batch_saved_bytes >= 0 )); then
        echo -e "${GR} = = > Net Space Saved:${NC} ${YELLOW}$(bytes_to_human "$batch_saved_bytes")${NC}"
    else
        echo -e "${YE} = = > Net Space Delta:${NC} ${YELLOW}$(bytes_to_human "$(( -batch_saved_bytes ))")${NC}"
    fi

    echo -e "${CYAN} = = > Batch Percent Change:${NC} ${YELLOW}${batch_delta_percent}%${NC}"
    echo -e "${RE} = = > Failed Outputs:${NC} ${YELLOW}$fail_count${NC}"
    echo -e "${CYAN} = = > Archival Ledger:${NC} ${GREEN}$ARCHIE_LEDGER${NC}"

    if [[ "$metadata_mode" != "minimal_skip" ]]; then
        echo -e "${CYAN} = = > Metadata Sidecar Folder:${NC} ${GREEN}$ARCHIE_META_DIR${NC}"
    fi

    if ((${#outputs[@]} > 0)); then
        archie_print_targets "New Archival Outputs" "${outputs[@]}"
    else
        echo -e "${YELLOW} = = > No New Archival Outputs Survived The Size-Gain Filter.${NC}"
        echo
    fi

    if ((${#outputs[@]} > 0)); then
        if ask_yes_no " = = > Build Tarball From New Archival Outputs? (y/n or 1/2): "; then
            tar_name="${prefix}ARCHIVE_SET.tar"
            if archie_build_tarball "$tar_name" "${outputs[@]}"; then
                echo -e "${GR} = = > Tarball Ready:${NC} ${CYAN}$tar_name${NC}"
            else
                echo -e "${YELLOW} = = > Tarball Was Not Built.${NC}"
            fi
            echo
        else
            echo -e "${YELLOW} = = > Tarball Step Skipped.${NC}"
            echo
        fi
    else
        echo -e "${YELLOW} = = > Tarball Prompt Skipped Because No Outputs Were Kept.${NC}"
        echo
    fi

    if ((${#source_output_pairs[@]} > 0)); then
        archie_show_danger_banner

        if ask_yes_no " = = > Delete Original Source Files After Successful Archival? (y/n or 1/2, default: n): "; then
            echo -e "${REB} = = > ORIGINAL DELETE PHASE ENABLED.${NC}"
            echo -e "${YELLOW} = = > Only sources with surviving archival outputs will be removed.${NC}"
            echo -e "${YELLOW} = = > Metadata sidecars / ledger remain for internal reference.${NC}"
            echo

            if ! ask_yes_no " = = > FINAL DELETE GATE :: Are You Absolutely Sure? (y/n or 1/2): "; then
                echo -e "${YELLOW} = = > Final Delete Gate Declined. Originals Preserved.${NC}"
                echo
                pause
                return 0
            fi

            for pair in "${source_output_pairs[@]}"; do
                src_from_pair="${pair%%|*}"
                out_from_pair="${pair#*|}"

                if [[ -f "$out_from_pair" && -f "$src_from_pair" ]]; then
                    rm -f -- "$src_from_pair"
                    echo -e "${GR} = = > Deleted Original:${NC} ${GREEN}$src_from_pair${NC}"
                    ((delete_success_count+=1)) || :
                fi
            done

            echo
            echo -e "${CYAN} = = > Originals Deleted After Verified Archival:${NC} ${YELLOW}$delete_success_count${NC}"
            echo
        else
            echo -e "${YELLOW} = = > Original Sources Preserved.${NC}"
            echo
        fi
    else
        echo -e "${YELLOW} = = > Original Delete Prompt Skipped Because No Successful Output Pairs Exist.${NC}"
        echo
    fi

    pause
}

# ------------------ ENTRYPOINT ------------------
main() {
    local missing=0

    for cmd in ffmpeg ffprobe awk sed grep stat df du tar; do
        if ! have_cmd "$cmd"; then
            echo -e "${REB} = = > Missing Required Command:${NC} ${YELLOW}$cmd${NC}"
            missing=1
        fi
    done

    if (( missing != 0 )); then
        echo
        echo -e "${REB} = = > One Or More Required Commands Are Missing. Cannot Continue.${NC}"
        exit 1
    fi

    run_archie
}

main "$@"
