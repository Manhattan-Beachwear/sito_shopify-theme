#!/bin/bash
# sync-all-themes.sh
# Central script to sync grandparent → parent → children
# Syncs entire directories EXCEPT specific excluded files

set -e

# ============================================
# CONFIGURATION
# ============================================
GRANDPARENT_REMOTE="upstream"
GRANDPARENT_BRANCH="main"
CHILD_REPOS=(
    "git@github.com:Manhattan-Beachwear/otis_shopify-theme.git"
    "git@github.com:Manhattan-Beachwear/col_shopify-theme.git"
    "git@github.com:Manhattan-Beachwear/sito_shopify-theme.git"
    "git@github.com:Manhattan-Beachwear/layday_shopify-theme.git"
)
CHILD_NAMES=("otis" "col" "sito" "layday")

SYNC_DIRS=(
    "sections"
    "snippets"
    "blocks"
    "assets"
    "locales"
)

# Files to EXCLUDE from sync (child-specific)
EXCLUDE_FILES=(
    "sections/footer-group.json"
    "sections/header-group.json"
)

# ============================================
# TEST MODE / DRY RUN
# ============================================
TEST_MODE=false
SKIP_PARENT_UPDATE=false
TEST_SINGLE_CHILD=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=true
            echo "🧪 TEST MODE ENABLED"
            echo "   - Will show what WOULD happen"
            echo "   - NO changes will be pushed"
            echo ""
            shift
            ;;
        --skip-parent)
            SKIP_PARENT_UPDATE=true
            echo "⏭️  Skipping parent update (testing children only)"
            echo ""
            shift
            ;;
        --only)
            TEST_SINGLE_CHILD="$2"
            echo "🎯 Testing single child: $TEST_SINGLE_CHILD"
            echo ""
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --test          Dry run - show what would happen without pushing"
            echo "  --skip-parent   Skip updating parent from grandparent"
            echo "  --only <child>  Only sync to one child (otis/col/sito/layday)"
            echo "  --help          Show this help"
            echo ""
            echo "Excluded files (child-specific):"
            for file in "${EXCLUDE_FILES[@]}"; do
                echo "  - $file"
            done
            echo ""
            echo "Examples:"
            echo "  $0 --test                    # See what would happen"
            echo "  $0 --test --only otis        # Test sync to just Otis"
            echo "  $0 --skip-parent --only otis # Sync to Otis without updating parent"
            echo "  $0                           # Full sync (updates parent + all children)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
done

echo "🔄 Starting grandparent → parent → children sync..."
echo "📁 Syncing directories: ${SYNC_DIRS[*]}"
echo "🚫 Excluding files: ${EXCLUDE_FILES[*]}"
echo ""

# ============================================
# STEP 1: Pull from Grandparent to Parent
# ============================================
if [[ "$SKIP_PARENT_UPDATE" == "false" ]]; then
    echo "📥 STEP 1: Pulling updates from grandparent (cascadiamarquee)..."
    
    # Ensure we're on main and clean
    if [[ $(git status --porcelain) ]]; then
        echo "❌ Working directory has uncommitted changes. Please commit or stash first."
        exit 1
    fi
    
    git checkout main
    git fetch $GRANDPARENT_REMOTE
    
    # Pull each directory from grandparent
    echo "Pulling directories from grandparent..."
    for dir in "${SYNC_DIRS[@]}"; do
        if git ls-tree -d $GRANDPARENT_REMOTE/$GRANDPARENT_BRANCH | grep -q "$dir"; then
            echo "  ✓ $dir/"
            if [[ "$TEST_MODE" == "false" ]]; then
                rm -rf "$dir"
                git checkout $GRANDPARENT_REMOTE/$GRANDPARENT_BRANCH -- "$dir"
                
                # Restore excluded files from parent
                for exclude in "${EXCLUDE_FILES[@]}"; do
                    if [[ "$exclude" == "$dir/"* ]]; then
                        if git show HEAD:"$exclude" > /dev/null 2>&1; then
                            echo "    ↩️  Restoring excluded: $exclude"
                            git checkout HEAD -- "$exclude"
                        fi
                    fi
                done
            else
                echo "    [TEST] Would update from grandparent"
                for exclude in "${EXCLUDE_FILES[@]}"; do
                    if [[ "$exclude" == "$dir/"* ]]; then
                        echo "    [TEST] Would restore: $exclude"
                    fi
                done
            fi
        else
            echo "  ⚠ $dir/ (not found in grandparent, skipping)"
        fi
    done
    
    # Check if there are changes
    if [[ "$TEST_MODE" == "false" ]]; then
        if git diff --quiet && git diff --cached --quiet; then
            echo "✅ Parent already up to date with grandparent!"
        else
            echo "📝 Committing changes to parent..."
            git add -A
            
            CHANGED_FILES=$(git diff --cached --name-only | wc -l | tr -d ' ')
            git commit -m "Sync from grandparent [$(date +%Y-%m-%d)]

Updated directories: ${SYNC_DIRS[*]}
Excluded files: ${EXCLUDE_FILES[*]}
Files changed: $CHANGED_FILES"
            
            git push origin main
            echo "✅ Parent updated with $CHANGED_FILES file changes!"
        fi
    else
        echo "[TEST] Would commit and push changes to parent"
    fi
else
    echo "⏭️  STEP 1: Skipped (--skip-parent flag used)"
fi

echo ""

# ============================================
# STEP 2: Push to Children
# ============================================
echo "📤 STEP 2: Pushing updates to children..."

TEMP_DIR=$(mktemp -d)
PARENT_DIR=$(pwd)
REVIEW_BRANCH="review/parent-sync-$(date +%Y-%m-%d-%H%M)"

# Filter children if --only flag used
if [[ -n "$TEST_SINGLE_CHILD" ]]; then
    FILTERED_REPOS=()
    FILTERED_NAMES=()
    for i in "${!CHILD_NAMES[@]}"; do
        if [[ "${CHILD_NAMES[$i]}" == "$TEST_SINGLE_CHILD" ]]; then
            FILTERED_REPOS=("${CHILD_REPOS[$i]}")
            FILTERED_NAMES=("${CHILD_NAMES[$i]}")
            break
        fi
    done
    if [[ ${#FILTERED_REPOS[@]} -eq 0 ]]; then
        echo "❌ Child '$TEST_SINGLE_CHILD' not found. Valid: ${CHILD_NAMES[*]}"
        exit 1
    fi
    CHILD_REPOS=("${FILTERED_REPOS[@]}")
    CHILD_NAMES=("${FILTERED_NAMES[@]}")
fi

for i in "${!CHILD_REPOS[@]}"; do
    CHILD_REPO="${CHILD_REPOS[$i]}"
    CHILD_NAME="${CHILD_NAMES[$i]}"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Syncing to: $CHILD_NAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ "$TEST_MODE" == "true" ]]; then
        echo "[TEST] Would clone, create branch, copy files, and push"
        echo "[TEST] Review branch: $REVIEW_BRANCH"
        echo "[TEST] Directories to sync: ${SYNC_DIRS[*]}"
        echo "[TEST] Files to preserve: ${EXCLUDE_FILES[*]}"
        continue
    fi
    
    cd "$TEMP_DIR"
    
    # Clone child repo
    echo "Cloning $CHILD_NAME..."
    git clone "$CHILD_REPO" "$CHILD_NAME" --depth 1 -q
    cd "$CHILD_NAME"
    
    # Create review branch
    git checkout -b "$REVIEW_BRANCH"
    
    # Backup excluded files before copying
    echo "Backing up excluded files..."
    mkdir -p .excluded-backup
    for exclude in "${EXCLUDE_FILES[@]}"; do
        if [[ -f "$exclude" ]]; then
            echo "  💾 $exclude"
            mkdir -p ".excluded-backup/$(dirname "$exclude")"
            cp "$exclude" ".excluded-backup/$exclude"
        fi
    done
    
    # Copy directories from parent
    echo "Copying directories..."
    for dir in "${SYNC_DIRS[@]}"; do
        if [[ -d "$PARENT_DIR/$dir" ]]; then
            FILE_COUNT=$(find "$PARENT_DIR/$dir" -type f | wc -l | tr -d ' ')
            echo "  ✓ $dir/ ($FILE_COUNT files)"
            rm -rf "$dir"
            cp -r "$PARENT_DIR/$dir" "$dir"
        else
            echo "  ⚠ $dir/ (not in parent, skipping)"
        fi
    done
    
    # Restore excluded files
    echo "Restoring excluded files..."
    for exclude in "${EXCLUDE_FILES[@]}"; do
        if [[ -f ".excluded-backup/$exclude" ]]; then
            echo "  ↩️  $exclude"
            mkdir -p "$(dirname "$exclude")"
            cp ".excluded-backup/$exclude" "$exclude"
        fi
    done
    rm -rf .excluded-backup
    
    # Check if there are changes
    if git diff --quiet; then
        echo "✅ $CHILD_NAME already up to date!"
        cd "$PARENT_DIR"
        continue
    fi
    
    # Show stats
    FILES_CHANGED=$(git diff --name-only | wc -l | tr -d ' ')
    
    # Commit and push
    git add -A
    git commit -m "Sync parent theme updates [$(date +%Y-%m-%d)]

Updated directories: ${SYNC_DIRS[*]}
Excluded (preserved): ${EXCLUDE_FILES[*]}
Files changed: $FILES_CHANGED

⚠️ REVIEW BEFORE MERGING TO MAIN"
    
    git push origin "$REVIEW_BRANCH"
    
    echo "✅ Review branch pushed: $REVIEW_BRANCH"
    echo "   Files changed: $FILES_CHANGED"
    echo "🔗 PR: https://github.com/Manhattan-Beachwear/${CHILD_NAME}_shopify-theme/compare/$REVIEW_BRANCH"
    
    cd "$PARENT_DIR"
done

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$TEST_MODE" == "true" ]]; then
    echo "🧪 TEST COMPLETE - No changes were made"
else
    echo "✅ SYNC COMPLETE!"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""