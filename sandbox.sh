#!/usr/bin/env bash
#
# sandbox.sh — Simple Git Worktree Sandbox Manager
#
# Usage:
#   ./sandbox.sh create              → Create a new sandbox from main
#   ./sandbox.sh cleanup [target]    → Remove the most recent sandbox (or specific one)
#   ./sandbox.sh list                → List all active sandboxes
#   ./sandbox.sh update [target]     → Update current/latest sandbox (or specific one)
#   ./sandbox.sh update --all        → Update all sandboxes

# === Configuration ===
MAIN_BRANCH="main"
SANDBOX_BASE_DIR="../git-worktree-manager_sandbox"   # All sandboxes will live here
REMOTE="origin"

# === Helper ===
timestamp() { date +"%Y%m%d-%H%M%S"; }

# === Helper function to find sandbox by pattern ===
find_sandbox() {
  local pattern="$1"
  local target_dir=""

  # Search by directory name or path first
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree[[:space:]]+(.+) ]]; then
      local dir="${BASH_REMATCH[1]}"
      if [[ "$dir" == *"git-worktree-manager-sandbox"* ]]; then
        local dir_name=$(basename "$dir")
        if [[ "$dir_name" == *"$pattern"* ]] || [[ "$dir" == *"$pattern"* ]]; then
          target_dir="$dir"
          break
        fi
      fi
    fi
  done < <(git worktree list --porcelain)

  # If not found by path, search by branch name
  if [ -z "$target_dir" ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^worktree[[:space:]]+(.+) ]]; then
        local dir="${BASH_REMATCH[1]}"
        if [[ "$dir" == *"git-worktree-manager-sandbox"* ]]; then
          local dir_branch
          dir_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
          if [[ "$dir_branch" == *"$pattern"* ]]; then
            target_dir="$dir"
            break
          fi
        fi
      fi
    done < <(git worktree list --porcelain)
  fi

  echo "$target_dir"
}

# === Helper function to get all sandbox directories ===
get_all_sandboxes() {
  local sandboxes=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree[[:space:]]+(.+) ]]; then
      local dir="${BASH_REMATCH[1]}"
      if [[ "$dir" == *"git-worktree-manager-sandbox"* ]]; then
        sandboxes+=("$dir")
      fi
    fi
  done < <(git worktree list --porcelain)
  printf '%s\n' "${sandboxes[@]}"
}

# === Helper function to get latest sandbox ===
get_latest_sandbox() {
  git worktree list --porcelain | \
    awk '/^worktree / {path=$2} /^HEAD / && path ~ /git-worktree-manager-sandbox/ {print path}' | \
    sort -r | \
    head -n 1
}

# === Helper function to update a single sandbox ===
update_single_sandbox() {
  local target_dir="$1"
  local branch
  branch=$(git -C "$target_dir" rev-parse --abbrev-ref HEAD)

  echo "🔄 Merging $MAIN_BRANCH into '$branch'..."
  if git -C "$target_dir" merge "$REMOTE/$MAIN_BRANCH" --no-edit; then
    echo "✅ Sandbox '$branch' updated successfully."
    return 0
  else
    echo "⚠️  Merge conflicts in '$branch'. Resolve manually in: $target_dir"
    return 1
  fi
}

# === Commands ===
create_sandbox() {
  local branch="nsega/sandbox/$(timestamp)"
  local dir="$SANDBOX_BASE_DIR/${branch//\//-}"

  echo "🔄 Updating $MAIN_BRANCH..."
  git fetch "$REMOTE" "$MAIN_BRANCH"

  echo "🪄 Creating sandbox branch '$branch' in '$dir'..."
  mkdir -p "$SANDBOX_BASE_DIR"
  git worktree add "$dir" -b "$branch" "$MAIN_BRANCH" || exit 1

  echo "✅ Sandbox created:"
  echo "  Directory: $dir"
  echo "  Branch:    $branch"
  echo ""
  echo "👉 cd $dir to start experimenting!"
}

cleanup_sandbox() {
  local target_dir

  if [ -n "$1" ]; then
    echo "🔍 Searching for sandbox matching: $1"
    target_dir=$(find_sandbox "$1")

    if [ -z "$target_dir" ]; then
      echo "❌ No sandbox found matching: $1"
      echo "💡 Run './sandbox.sh list' to see available sandboxes"
      exit 1
    fi
  else
    echo "🧹 Cleaning up latest sandbox..."
    target_dir=$(get_latest_sandbox)

    if [ -z "$target_dir" ]; then
      echo "❌ No sandbox found."
      exit 0
    fi
  fi

  local branch
  branch=$(git -C "$target_dir" rev-parse --abbrev-ref HEAD)

  echo "Removing worktree: $target_dir"
  git worktree remove "$target_dir" --force
  git branch -D "$branch" 2>/dev/null || true
  echo "✅ Sandbox '$branch' removed."
}

list_sandboxes() {
  echo "🗂️ Active sandboxes:"
  git worktree list | grep sandbox || echo "(none)"
}

update_sandbox() {
  local target_dirs=()

  # Determine which sandbox(es) to update
  if [[ "$1" == "--all" ]]; then
    echo "🔄 Finding all sandboxes..."
    mapfile -t target_dirs < <(get_all_sandboxes)

    if [ ${#target_dirs[@]} -eq 0 ]; then
      echo "❌ No sandboxes found."
      exit 1
    fi
    echo "Found ${#target_dirs[@]} sandbox(es) to update."

  elif [ -n "$1" ]; then
    echo "🔍 Searching for sandbox matching: $1"
    local found_dir
    found_dir=$(find_sandbox "$1")

    if [ -z "$found_dir" ]; then
      echo "❌ No sandbox found matching: $1"
      echo "💡 Run './sandbox.sh list' to see available sandboxes"
      exit 1
    fi
    target_dirs=("$found_dir")

  elif [[ "$PWD" == *"git-worktree-manager-sandbox"* ]] && git rev-parse --git-dir >/dev/null 2>&1; then
    target_dirs=("$PWD")
    echo "🔄 Updating current sandbox: $PWD"

  else
    echo "🔄 Finding latest sandbox..."
    local latest
    latest=$(get_latest_sandbox)

    if [ -z "$latest" ]; then
      echo "❌ No sandbox found."
      exit 1
    fi
    target_dirs=("$latest")
    echo "🔄 Updating latest sandbox: $latest"
  fi

  # Fetch once before updating
  echo "📥 Fetching latest $MAIN_BRANCH..."
  git fetch "$REMOTE" "$MAIN_BRANCH"

  # Update each sandbox
  local success=0
  local failed=0
  for target_dir in "${target_dirs[@]}"; do
    if update_single_sandbox "$target_dir"; then
      ((success++))
    else
      ((failed++))
    fi
  done

  # Summary for multiple updates
  if [ ${#target_dirs[@]} -gt 1 ]; then
    echo ""
    echo "📊 Update summary: $success succeeded, $failed failed"
    [ $failed -gt 0 ] && exit 1
  fi
}

case "$1" in
  create)  create_sandbox ;;
  cleanup) cleanup_sandbox "$2" ;;
  list)    list_sandboxes ;;
  update)  update_sandbox "$2" ;;
  *) echo "Usage: $0 {create|cleanup [target]|list|update [target|--all]}" ;;
esac
