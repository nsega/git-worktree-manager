# Git Worktree Manager

A Bash script for managing Git worktrees as **named feature branches** (PR-bound) or **throwaway sandboxes** (timestamped experiments). Optimized for working alongside Claude Code: shared memory, linked `.claude/` config, and `.envrc`/`tmp` symlinked from a canonical repo.

## What is Git Worktree?

Git worktrees let you check out multiple branches in separate directories from a single repository. Useful for:
- Parallel feature work without stashing or switching branches
- Quick experiments that don't pollute your main checkout
- Running tests on multiple branches at once
- Keeping a stable "anchor" checkout while iterating elsewhere

## Features

- **Two worktree styles**:
  - **Named (topic)**: `create <topic>` → `<repo>-worktrees/<topic>/` on `<user>/<topic>` — for PR-bound work
  - **Throwaway (sandbox)**: `create` (no args) → `<repo>-worktrees/sandbox/<timestamp>/` on `<user>/sandbox/<timestamp>` — for experiments
- **Smart pattern matching**: cleanup/update by partial dir name or branch name
- **Batch updates**: `update --all` merges `main` into every worktree
- **Auto-detect current worktree**: bare `update` / `cleanup` operates on cwd if it's a worktree, else the most recent one
- **Claude Code integration**: each worktree gets symlinks to a shared memory dir, shared `.claude/` subdirs (plans, agents, commands, skills), and the canonical `.envrc` / `tmp`
- **Memory relink helper**: `relink-memory` repairs Claude Code memory symlinks across all worktrees

## Requirements

- Git 2.5+ (worktree support)
- Bash 4.0+
- Unix-like environment (Linux, macOS, WSL)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nsega/git-worktree-manager.git
   cd git-worktree-manager
   ```

2. Make the script executable:
   ```bash
   chmod +x worktree.sh
   ```

3. **Edit the configuration block** at the top of `worktree.sh` to match your GitHub username and repo name:
   ```bash
   GITHUB_USER_NAME="your-github-username"
   GITHUB_REPOSITORY="your-repo-name"
   ```

4. (Optional) Add an alias to your shell rc:
   ```bash
   alias wt="/path/to/worktree.sh"
   ```

## Usage

### Create a named worktree (PR-bound)

```bash
./worktree.sh create JIRA-101-enable-busy-signaling
```

- Directory: `../<repo>-worktrees/JIRA-101-enable-busy-signaling/`
- Branch: `<user>/JIRA-101-enable-busy-signaling`

Topics are sanitized to kebab-case; case is preserved (ticket IDs like `JIRA-101` stay uppercase).

### Create a throwaway sandbox (no topic)

```bash
./worktree.sh create
```

- Directory: `../<repo>-worktrees/sandbox/YYYY-MM-DD-HHMMSS/`
- Branch: `<user>/sandbox/YYYY-MM-DD-HHMMSS`

### List active worktrees

```bash
./worktree.sh list
```

Prints a table of directory, commit, and branch for every worktree managed by this script.

### Update worktrees (merge `origin/main`)

```bash
./worktree.sh update                  # current worktree (if cwd is one), else latest
./worktree.sh update <pattern>        # match by dir or branch substring
./worktree.sh update proto api        # multiple targets
./worktree.sh update --all            # every worktree
```

Merge conflicts are reported per-worktree; the script continues with the rest.

### Clean up a worktree

```bash
./worktree.sh cleanup                 # latest worktree
./worktree.sh cleanup <pattern>       # specific worktree by dir or branch substring
```

Removes the worktree directory, deletes its branch (sandbox branches are force-deleted; topic branches use `git branch -d` which refuses unmerged work), and unlinks the Claude Code memory symlink.

### Relink Claude Code memory

```bash
./worktree.sh relink-memory              # current worktree (or all if cwd isn't one)
./worktree.sh relink-memory <pattern>    # specific worktree
./worktree.sh relink-memory --all        # every worktree
./worktree.sh relink-memory --all --force  # back up and replace any real memory dirs
```

Repoints each worktree's `~/.claude/projects/<slug>/memory` at the canonical repo's memory dir. Useful as a one-time fix for worktrees created before the slug bug was fixed.

## Configuration

All settings live at the top of `worktree.sh`:

```bash
MAIN_BRANCH="main"                       # Default branch
GITHUB_USER_NAME="nsega"                 # Used as branch prefix
GITHUB_REPOSITORY="git-worktree-manager" # Drives worktree dir name + canonical repo path
REMOTE="origin"                          # Remote name
```

Derived paths (you usually don't need to touch these):
- `WORKTREES_BASE_DIR="../$GITHUB_REPOSITORY-worktrees"`
- `SANDBOX_BASE_DIR="$WORKTREES_BASE_DIR/sandbox"`
- `CANONICAL_REPO="$HOME/src/github.com/$GITHUB_USER_NAME/$GITHUB_REPOSITORY"`
- `CANONICAL_MEMORY="$HOME/.claude/projects/<auto-slug>/memory"`

`CANONICAL_REPO` assumes the layout `~/src/github.com/<user>/<repo>` — adjust if your local layout differs.

## What gets linked into each new worktree

- `.envrc` → `$CANONICAL_REPO/.envrc`
- `tmp/` → `$CANONICAL_REPO/tmp`
- `.claude/{plans,agents,commands,skills}` — only those that exist in the canonical repo
- `~/.claude/projects/<slug>/memory` → canonical repo's memory dir (so Claude Code sees the same persistent memory across all worktrees)

## Recommended layout & discipline

```
~/src/github.com/<user>/
  <repo>/                            Primary git anchor — keep on main/develop, don't do feature work here
  <repo>-worktrees/<topic>/          PR-bound feature work
  <repo>-worktrees/sandbox/<ts>/     Throwaway experiments
```

Rule of thumb: if you're about to `cd` into the anchor repo to start coding on a ticket, run `./worktree.sh create <ticket>` instead.

## Troubleshooting

- **"No worktree found matching: …"** — run `./worktree.sh list` to see available targets.
- **Merge conflicts during update** — the worktree is left in a conflicted state; resolve manually in that directory.
- **Branch `<user>/foo` has unmerged or unpushed work — keeping it** — cleanup is refusing to delete a topic branch with work that isn't on `main` or the remote. Inspect with `git log main..<branch>`, then force-delete with `git branch -D <branch>` if you're sure.
- **"Canonical memory dir not found"** — the script expects the canonical repo at `$CANONICAL_REPO` with a memory dir under `~/.claude/projects/`. Either run `claude` once in the canonical repo to create it, or adjust `CANONICAL_REPO` to match your layout.
- **Permission denied** — `chmod +x worktree.sh`.

## Contributing

Issues and PRs welcome.

## License

MIT.
