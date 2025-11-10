# Git Worktree Manager

A simple and powerful Bash script for managing Git worktree sandboxes. Create isolated development environments for experimentation, feature development, or testing without disrupting your main working directory.

## What is Git Worktree?

Git worktrees allow you to check out multiple branches of a repository simultaneously in separate directories. This is useful for:
- Testing changes without switching branches
- Working on multiple features in parallel
- Quick code reviews without stashing changes
- Running tests on different branches simultaneously

## Features

- **Create Sandboxes**: Instantly create new isolated worktrees from your main branch
- **Smart Cleanup**: Remove sandboxes by name, branch, or timestamp pattern
- **List Management**: View all active sandboxes at a glance
- **Update Sandboxes**: Merge latest changes from main into your sandboxes
- **Batch Updates**: Update all sandboxes at once with `--all` flag
- **Auto-detection**: When run inside a sandbox, automatically operates on the current sandbox

## Requirements

- Git 2.5 or higher (for worktree support)
- Bash 4.0 or higher
- Unix-like environment (Linux, macOS, WSL)

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/nsega/git-worktree-manager.git
   cd git-worktree-manager
   ```

2. Make the script executable:
   ```bash
   chmod +x sandbox.sh
   ```

3. (Optional) Add to your PATH or create an alias:
   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   alias sandbox="/path/to/git-worktree-manager/sandbox.sh"
   ```

## Usage

### Create a New Sandbox

```bash
./sandbox.sh create
```

This will:
- Fetch the latest changes from the main branch
- Create a new branch named `nsega/sandbox/YYYYMMDD-HHMMSS`
- Set up a worktree in a separate directory
- Display the path for you to navigate to

Example output:
```
🔄 Updating main...
🪄 Creating sandbox branch 'nsega/sandbox/20250110-143022' in '../git-worktree-manager_sandbox/nsega-sandbox-20250110-143022'...
✅ Sandbox created:
  Directory: ../git-worktree-manager_sandbox/nsega-sandbox-20250110-143022
  Branch:    nsega/sandbox/20250110-143022

👉 cd ../git-worktree-manager_sandbox/nsega-sandbox-20250110-143022 to start experimenting!
```

### List Active Sandboxes

```bash
./sandbox.sh list
```

Shows all current sandbox worktrees with their paths and branches.

### Update a Sandbox

Update the latest sandbox (or current if you're inside one):
```bash
./sandbox.sh update
```

Update a specific sandbox by pattern (matches directory name, path, or branch):
```bash
./sandbox.sh update 20250110-143022
./sandbox.sh update feature-name
```

Update all sandboxes at once:
```bash
./sandbox.sh update --all
```

The update command will merge the latest changes from the main branch into your sandbox branch.

### Clean Up a Sandbox

Remove the latest sandbox:
```bash
./sandbox.sh cleanup
```

Remove a specific sandbox by pattern:
```bash
./sandbox.sh cleanup 20250110-143022
./sandbox.sh cleanup feature-name
```

This will remove the worktree and delete the branch.

## Configuration

You can customize the script by editing these variables at the top of `sandbox.sh`:

```bash
MAIN_BRANCH="main"                                  # Your default branch
SANDBOX_BASE_DIR="../git-worktree-manager_sandbox"  # Where sandboxes are created
REMOTE="origin"                                      # Remote repository name
```

## How It Works

1. **Create**: Creates a new branch from main and sets up a linked worktree in a separate directory
2. **Cleanup**: Removes the worktree directory and deletes the associated branch
3. **List**: Queries git for all worktrees and filters those matching the sandbox pattern
4. **Update**: Fetches the latest main branch and merges it into the sandbox branch

All sandboxes share the same Git object database, making them lightweight and fast to create.

## Tips

- Sandboxes are timestamped, making it easy to identify when they were created
- You can have multiple sandboxes active at the same time
- Each sandbox is a full working directory with its own index and HEAD
- Changes in one sandbox don't affect others or your main working directory
- Use sandboxes for quick experiments, then clean them up when done

## Troubleshooting

**"No sandbox found"**: Run `./sandbox.sh list` to see available sandboxes and verify your search pattern

**Merge conflicts during update**: The script will notify you and preserve the conflicted state. Navigate to the sandbox directory to resolve conflicts manually.

**Permission denied**: Ensure the script is executable with `chmod +x sandbox.sh`

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests.

## License

MIT License - feel free to use and modify as needed.
