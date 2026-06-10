#!/usr/bin/env bash
#
# worktree.sh — Git Worktree Manager (named features + throwaway sandboxes)
#
# Usage:
#   ./worktree.sh create [topic]      → Topic → ../$GITHUB_REPOSITORY-worktrees/<topic>  on  $GITHUB_USER_NAME/<topic>
#                                      No topic → ../$GITHUB_REPOSITORY-worktrees/sandbox/<ts>  on  $GITHUB_USER_NAME/sandbox/<ts>
#   ./worktree.sh cleanup [target]    → Remove the most recent worktree (or specific one)
#   ./worktree.sh list                → List all active worktrees
#   ./worktree.sh update [target...]  → Merge main into current/latest worktree (or specific)
#   ./worktree.sh update --all        → Update all worktrees
#   ./worktree.sh help                → Full help

# === Configuration ===
MAIN_BRANCH="main"
# Configure these to your own GitHub username and repository name.
GITHUB_USER_NAME="nsega"
GITHUB_REPOSITORY="git-worktree-manager"
WORKTREES_BASE_DIR="../$GITHUB_REPOSITORY-worktrees"             # Named (topic) worktrees live here
SANDBOX_BASE_DIR="$WORKTREES_BASE_DIR/sandbox"       # Throwaway (no-topic) worktrees live here
REMOTE="origin"
CANONICAL_REPO="$HOME/src/github.com/$GITHUB_USER_NAME/$GITHUB_REPOSITORY"
# Claude Code's config dir. Honors CLAUDE_CONFIG_DIR (where session/memory data
# lives, e.g. ~/.claude-work); falls back to the default ~/.claude.
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CANONICAL_MEMORY="$CLAUDE_CONFIG_DIR/projects/$(echo "$CANONICAL_REPO" | sed 's|[^a-zA-Z0-9]|-|g')/memory"
CLAUDE_SHARED_SUBDIRS=(plans agents commands skills)

# === Helper ===
timestamp() { date +"%Y%m%d-%H%M%S"; }
today()     { date +"%Y-%m-%d"; }

# Match worktree paths managed by this script (new layout or legacy).
# Covers both named topic worktrees ($GITHUB_REPOSITORY-worktrees/<topic>) and
# throwaway sandboxes ($GITHUB_REPOSITORY-worktrees/sandbox/...), plus legacy $GITHUB_REPOSITORY-sandbox/...
is_sandbox_path() {
  [[ "$1" == *"$GITHUB_REPOSITORY-worktrees/"* ]] || [[ "$1" == *"$GITHUB_REPOSITORY-sandbox"* ]]
}

# Sanitize a free-form topic into a filesystem-safe slug.
# Preserves case (so ticket IDs like JIRA-101 stay uppercase).
sanitize_topic() {
  echo "$1" | sed -E 's/[^a-zA-Z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Compute the ~/.claude/projects/ slug for a given absolute path.
# Claude Code replaces any non-alphanumeric character (e.g. '/', '.') with '-',
# so /Users/x/src/github.com/foo → -Users-x-src-github-com-foo.
path_to_claude_slug() {
  echo "$1" | sed 's|[^a-zA-Z0-9]|-|g'
}

# === Helper function to find sandbox by pattern (case-insensitive) ===
find_sandbox() {
  local pattern="$1"
  local target_dir=""
  shopt -s nocasematch

  # Search by directory name or path first
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree[[:space:]]+(.+) ]]; then
      local dir="${BASH_REMATCH[1]}"
      if is_sandbox_path "$dir"; then
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
        if is_sandbox_path "$dir"; then
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

  shopt -u nocasematch
  echo "$target_dir"
}

# === Helper function to get all sandbox directories ===
get_all_sandboxes() {
  local sandboxes=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree[[:space:]]+(.+) ]]; then
      local dir="${BASH_REMATCH[1]}"
      if is_sandbox_path "$dir"; then
        sandboxes+=("$dir")
      fi
    fi
  done < <(git worktree list --porcelain)
  printf '%s\n' "${sandboxes[@]}"
}

# === Helper function to get latest sandbox ===
get_latest_sandbox() {
  local latest_mtime=0 latest_dir="" m
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    m=$(stat -f %m "$dir" 2>/dev/null || stat -c %Y "$dir" 2>/dev/null || echo 0)
    if (( m > latest_mtime )); then
      latest_mtime=$m
      latest_dir=$dir
    fi
  done < <(get_all_sandboxes)
  echo "$latest_dir"
}

# === Symlink shared .claude/ subdirs that exist in the canonical repo ===
link_claude_dirs() {
  local dir="$1"
  mkdir -p "$dir/.claude"
  for sub in "${CLAUDE_SHARED_SUBDIRS[@]}"; do
    local src="$CANONICAL_REPO/.claude/$sub"
    local dest="$dir/.claude/$sub"
    if [ -d "$src" ] && [ ! -e "$dest" ]; then
      ln -s "$src" "$dest"
      echo "🔗 Linked .claude/$sub"
    fi
  done
}

# === Symlink the worktree's Claude Code memory dir to the canonical one ===
link_claude_memory() {
  local abs_dir="$1"
  if [ ! -d "$CANONICAL_MEMORY" ]; then
    echo "⚠️  Canonical memory dir not found: $CANONICAL_MEMORY (skipping)"
    return 0
  fi
  local slug
  slug=$(path_to_claude_slug "$abs_dir")
  local proj_dir="$CLAUDE_CONFIG_DIR/projects/$slug"
  local memory_link="$proj_dir/memory"

  mkdir -p "$proj_dir"
  if [ -L "$memory_link" ] || [ -e "$memory_link" ]; then
    echo "ℹ️  Memory already present at $memory_link — skipping"
    return 0
  fi
  ln -s "$CANONICAL_MEMORY" "$memory_link"
  echo "🔗 Linked Claude memory → canonical $GITHUB_REPOSITORY memory"
}

# === Buggy-slug encoder used by older versions of this script ===
# Only replaced '/' → '-', leaving '.' intact. Used to detect+clean stray dirs.
buggy_claude_slug() {
  echo "$1" | sed 's|/|-|g'
}

# === If a stray project dir from the old buggy slug exists, clean it up. ===
# Safe: only removes if the dir contains nothing but our memory symlink.
cleanup_stray_buggy_slug() {
  local abs_dir="$1"
  local correct stray
  correct=$(path_to_claude_slug "$abs_dir")
  stray=$(buggy_claude_slug "$abs_dir")
  [ "$correct" = "$stray" ] && return 0   # no '.' in path, nothing stray possible

  local stray_dir="$CLAUDE_CONFIG_DIR/projects/$stray"
  [ ! -d "$stray_dir" ] && return 0

  if [ -L "$stray_dir/memory" ]; then
    rm "$stray_dir/memory"
  fi
  if [ -z "$(ls -A "$stray_dir" 2>/dev/null)" ]; then
    rmdir "$stray_dir"
    echo "🧹 Removed stray buggy-slug project dir: $stray_dir"
  else
    echo "⚠️  Stray buggy-slug dir has other contents — leaving alone: $stray_dir"
  fi
}

# === Make the worktree's memory dir point at the canonical $GITHUB_REPOSITORY memory ===
# Handles every state the dir can be in: already correct, wrong symlink,
# real empty dir, or real non-empty dir (backed up only when --force is set).
relink_claude_memory_for() {
  local abs_dir="$1"
  local force="${2:-0}"

  if [ ! -d "$CANONICAL_MEMORY" ]; then
    echo "⚠️  Canonical memory dir not found: $CANONICAL_MEMORY"
    return 1
  fi

  local slug proj_dir memory
  slug=$(path_to_claude_slug "$abs_dir")
  proj_dir="$CLAUDE_CONFIG_DIR/projects/$slug"
  memory="$proj_dir/memory"

  mkdir -p "$proj_dir"

  if [ -L "$memory" ]; then
    local current
    current=$(readlink "$memory")
    if [ "$current" = "$CANONICAL_MEMORY" ]; then
      echo "✅ $abs_dir → already linked to canonical memory"
      return 0
    fi
    echo "🔗 $abs_dir → replacing symlink (was → $current)"
    rm "$memory"
    ln -s "$CANONICAL_MEMORY" "$memory"
    return 0
  fi

  if [ -d "$memory" ]; then
    if [ -z "$(ls -A "$memory" 2>/dev/null)" ]; then
      rmdir "$memory"
      ln -s "$CANONICAL_MEMORY" "$memory"
      echo "✅ $abs_dir → empty memory dir replaced with symlink"
      return 0
    fi
    if [ "$force" != "1" ]; then
      echo "⚠️  $abs_dir → real memory dir has contents; skipping"
      echo "    Path: $memory"
      echo "    Re-run with --force to back it up and relink."
      return 1
    fi
    local backup="${memory}.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$memory" "$backup"
    ln -s "$CANONICAL_MEMORY" "$memory"
    echo "✅ $abs_dir → linked (existing memory backed up to $backup)"
    return 0
  fi

  ln -s "$CANONICAL_MEMORY" "$memory"
  echo "✅ $abs_dir → linked"
}

# === Remove the symlinked memory + empty project dir for a worktree path ===
unlink_claude_memory() {
  local abs_dir="$1"
  local slug
  slug=$(path_to_claude_slug "$abs_dir")
  local proj_dir="$CLAUDE_CONFIG_DIR/projects/$slug"
  local memory_link="$proj_dir/memory"

  if [ -L "$memory_link" ]; then
    rm "$memory_link"
    echo "🧹 Removed memory symlink: $memory_link"
  fi
  # Remove the project dir only if it's now empty (don't clobber real session data).
  if [ -d "$proj_dir" ] && [ -z "$(ls -A "$proj_dir" 2>/dev/null)" ]; then
    rmdir "$proj_dir"
    echo "🧹 Removed empty project dir: $proj_dir"
  fi
}

# === Delete a worktree's branch with appropriate safety ===
# Sandbox branches ($GITHUB_USER_NAME/sandbox/*) are force-deleted — they're throwaway.
# Topic branches use `git branch -d` (refuses if not merged into HEAD/upstream).
delete_worktree_branch() {
  local branch="$1"

  if [[ "$branch" == "$GITHUB_USER_NAME/sandbox/"* ]]; then
    git branch -D "$branch" 2>/dev/null || true
    return 0
  fi

  if git branch -d "$branch" 2>/dev/null; then
    echo "✅ Deleted branch '$branch'."
    return 0
  fi

  echo "⚠️  Branch '$branch' has unmerged or unpushed work — keeping it."
  echo "    Inspect: git log $MAIN_BRANCH..$branch"
  echo "    Force delete (destructive): git branch -D $branch"
  return 1
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
  local topic="${1:-}"
  local dir branch base_dir
  if [ -n "$topic" ]; then
    local topic_clean
    topic_clean=$(sanitize_topic "$topic")
    if [ -z "$topic_clean" ]; then
      echo "❌ Topic '$topic' sanitized to empty string. Use alphanumeric characters."
      exit 1
    fi
    base_dir="$WORKTREES_BASE_DIR"
    dir="$base_dir/${topic_clean}"
    branch="$GITHUB_USER_NAME/${topic_clean}"
  else
    local stamp
    stamp="$(today)-$(date +%H%M%S)"
    base_dir="$SANDBOX_BASE_DIR"
    dir="$base_dir/${stamp}"
    branch="$GITHUB_USER_NAME/sandbox/${stamp}"
  fi

  echo "🔄 Updating $MAIN_BRANCH..."
  git fetch "$REMOTE" "$MAIN_BRANCH"

  echo "🪄 Creating branch '$branch' in '$dir'..."
  mkdir -p "$base_dir"
  git worktree add "$dir" -b "$branch" "$MAIN_BRANCH" || exit 1

  local abs_dir
  abs_dir=$(cd "$dir" && pwd)

  echo "🔗 Linking .envrc into worktree..."
  ln -s "$CANONICAL_REPO/.envrc" "$abs_dir/.envrc"

  link_claude_dirs "$abs_dir"

  echo "🔗 Linking tmp into worktree..."
  ln -s "$CANONICAL_REPO/tmp" "$abs_dir/tmp"

  link_claude_memory "$abs_dir"

  echo "✅ Worktree created:"
  echo "  Directory: $abs_dir"
  echo "  Branch:    $branch"
  echo ""
  echo "👉 cd $abs_dir to start experimenting!"
}

cleanup_sandbox() {
  local target_dir
  
  if [ -n "$1" ]; then
    echo "🔍 Searching for worktree matching: $1"
    target_dir=$(find_sandbox "$1")
    
    if [ -z "$target_dir" ]; then
      echo "❌ No worktree found matching: $1"
      echo "💡 Run './worktree.sh list' to see available worktrees"
      exit 1
    fi
  else
    echo "🧹 Cleaning up latest sandbox..."
    target_dir=$(get_latest_sandbox)
    
    if [ -z "$target_dir" ]; then
      echo "❌ No worktree found."
      exit 0
    fi
  fi
  
  local branch
  branch=$(git -C "$target_dir" rev-parse --abbrev-ref HEAD)
  
  echo "Removing worktree: $target_dir"
  local abs_target
  abs_target=$(cd "$target_dir" 2>/dev/null && pwd || echo "$target_dir")
  git worktree remove "$target_dir" --force
  delete_worktree_branch "$branch"
  unlink_claude_memory "$abs_target"
  echo "✅ Worktree at '$target_dir' removed."
}

list_sandboxes() {
  local sandboxes=()
  mapfile -t sandboxes < <(get_all_sandboxes)

  if [ ${#sandboxes[@]} -eq 0 ]; then
    echo "(none)"
    return
  fi

  # Collect data
  local names=() commits=() branches=()
  local max_name=9 max_commit=6 max_branch=6  # header widths
  for dir in "${sandboxes[@]}"; do
    local name commit branch
    name=$(basename "$dir")
    commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    names+=("$name")
    commits+=("$commit")
    branches+=("$branch")
    (( ${#name} > max_name )) && max_name=${#name}
    (( ${#commit} > max_commit )) && max_commit=${#commit}
    (( ${#branch} > max_branch )) && max_branch=${#branch}
  done

  # Print table
  printf "%-${max_name}s  %-${max_commit}s  %-${max_branch}s\n" "Directory" "Commit" "Branch"
  printf "%-${max_name}s  %-${max_commit}s  %-${max_branch}s\n" \
    "$(printf '%*s' "$max_name" '' | tr ' ' '-')" \
    "$(printf '%*s' "$max_commit" '' | tr ' ' '-')" \
    "$(printf '%*s' "$max_branch" '' | tr ' ' '-')"
  for i in "${!names[@]}"; do
    printf "%-${max_name}s  %-${max_commit}s  %-${max_branch}s\n" "${names[$i]}" "${commits[$i]}" "${branches[$i]}"
  done
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
    for pattern in "$@"; do
      echo "🔍 Searching for worktree matching: $pattern"
      local found_dir
      found_dir=$(find_sandbox "$pattern")

      if [ -z "$found_dir" ]; then
        echo "❌ No worktree found matching: $pattern"
        echo "💡 Run './worktree.sh list' to see available worktrees"
        exit 1
      fi
      target_dirs+=("$found_dir")
    done

  elif [[ "$PWD" == *"$GITHUB_REPOSITORY-sandbox"* ]] && git rev-parse --git-dir >/dev/null 2>&1; then
    target_dirs=("$PWD")
    echo "🔄 Updating current sandbox: $PWD"
    
  else
    echo "🔄 Finding latest sandbox..."
    local latest
    latest=$(get_latest_sandbox)
    
    if [ -z "$latest" ]; then
      echo "❌ No worktree found."
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

relink_memory() {
  local force=0
  local patterns=()
  local mode=""   # "" | "all"

  for arg in "$@"; do
    case "$arg" in
      --force) force=1 ;;
      --all)   mode="all" ;;
      *)       patterns+=("$arg") ;;
    esac
  done

  local target_dirs=()

  if [ "$mode" = "all" ]; then
    mapfile -t target_dirs < <(get_all_sandboxes)
  elif [ ${#patterns[@]} -gt 0 ]; then
    for pattern in "${patterns[@]}"; do
      echo "🔍 Searching for worktree matching: $pattern"
      local found
      found=$(find_sandbox "$pattern")
      if [ -z "$found" ]; then
        echo "❌ No worktree found matching: $pattern"
        exit 1
      fi
      target_dirs+=("$found")
    done
  elif is_sandbox_path "$PWD" && git rev-parse --git-dir >/dev/null 2>&1; then
    target_dirs=("$PWD")
  else
    echo "🔄 No target given — relinking all worktrees..."
    mapfile -t target_dirs < <(get_all_sandboxes)
  fi

  if [ ${#target_dirs[@]} -eq 0 ]; then
    echo "❌ No worktrees to relink."
    exit 1
  fi

  local success=0 failed=0
  for dir in "${target_dirs[@]}"; do
    local abs
    abs=$(cd "$dir" 2>/dev/null && pwd || echo "$dir")
    cleanup_stray_buggy_slug "$abs"
    if relink_claude_memory_for "$abs" "$force"; then
      ((success++))
    else
      ((failed++))
    fi
  done

  if [ ${#target_dirs[@]} -gt 1 ]; then
    echo ""
    echo "📊 Relink summary: $success linked, $failed skipped"
    [ $failed -gt 0 ] && exit 1
  fi
}

print_help() {
  cat <<EOF
worktree.sh — Git worktree manager for $GITHUB_REPOSITORY (named features + throwaway sandboxes)

USAGE
  ./worktree.sh <command> [args]

COMMANDS
  create [topic]         Create a new worktree branched from $MAIN_BRANCH.

                         With topic (feature-ready, PR-bound):
                           Directory: $WORKTREES_BASE_DIR/<topic>/
                           Branch:    $GITHUB_USER_NAME/<topic>

                         Without topic (throwaway sandbox):
                           Directory: $SANDBOX_BASE_DIR/YYYY-MM-DD-HHMMSS/
                           Branch:    $GITHUB_USER_NAME/sandbox/YYYY-MM-DD-HHMMSS

                         Topic is sanitized to a kebab-case slug; case is
                         preserved so ticket IDs like JIRA-101 stay uppercase.

  list                   List all active worktrees (new + legacy paths).

  update [target...]     Merge origin/$MAIN_BRANCH into one or more worktrees.
                         With no args: updates the current worktree (if cwd is one)
                         or the most recently created worktree otherwise.
                         Targets may be partial dir-name or branch-name matches.

  update --all           Update every worktree.

  cleanup, clean         Remove a worktree, delete its branch (safely for
    [target]             non-sandbox branches), and unlink its Claude Code
                         memory symlink. With no arg, removes the most recently
                         created worktree.

  relink-memory          Repoint a worktree's Claude Code memory dir at the
    [target...|--all]    canonical $GITHUB_REPOSITORY memory. Useful as a one-time fix for
    [--force]            worktrees created before the slug bug was fixed.
                         With no arg: current worktree (if cwd is one), else all.
                         --force backs up and replaces a non-empty real memory dir.
                         Also removes any stray buggy-slug project dirs.

  help, -h, --help       Show this help text.

WHAT GETS LINKED INTO A NEW WORKTREE
  - .envrc                  → $CANONICAL_REPO/.envrc
  - tmp/                    → $CANONICAL_REPO/tmp
  - .claude/{plans,agents,commands,skills}  (only those that exist in the canonical repo)
  - ~/.claude/projects/<slug>/memory        → canonical $GITHUB_REPOSITORY memory dir
    (so Claude Code sees the same persistent memory across all worktrees)

EXAMPLES
  ./worktree.sh create JIRA-101-enable-busy-signaling
  ./worktree.sh create                          # throwaway sandbox
  ./worktree.sh list
  ./worktree.sh update proto
  ./worktree.sh update --all
  ./worktree.sh cleanup JIRA-101-enable-busy-signaling
  ./worktree.sh relink-memory --all

LAYOUT & DISCIPLINE
  Give each directory one purpose. Don't mix feature work with the git anchor.

    ~/src/.../$GITHUB_USER_NAME/
      $GITHUB_REPOSITORY/                     Primary git anchor (.git lives here; symlink
                                  source for every other worktree). Keep on a
                                  stable home branch (main/develop). Do NOT
                                  do feature work here.

      $GITHUB_REPOSITORY-main/                Optional always-fresh main. Useful as a
                                  read-only reference for diff/grep, or as
                                  the target of an automated update-main.sh
                                  cron job. Safe to delete if unused.

      $GITHUB_REPOSITORY-worktrees/<topic>/   All PR-bound feature work. Created by
                                  './worktree.sh create <topic>'.

      $GITHUB_REPOSITORY-worktrees/sandbox/   Throwaway experiments. Created by
        <YYYY-MM-DD-HHMMSS>/      './worktree.sh create' with no args.

  Rule of thumb: if you're about to 'cd' into $GITHUB_REPOSITORY/ to start coding on a
  new ticket, stop and run './worktree.sh create <ticket>' instead.
EOF
}

case "$1" in
  create)            shift; create_sandbox "$@" ;;
  cleanup|clean)     cleanup_sandbox "$2" ;;
  list|ls)           list_sandboxes ;;
  update)            shift; update_sandbox "$@" ;;
  relink-memory)     shift; relink_memory "$@" ;;
  help|-h|--help|"") print_help ;;
  *)                 echo "Unknown command: $1"; echo; print_help; exit 1 ;;
esac
