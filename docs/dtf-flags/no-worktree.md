# DTF: --no-worktree
Read when the arguments contain `--no-worktree`.

- Work in the **current directory** — do not create a worktree or branch
- Skip "tell orchestrator to clean up" messaging
- The user is responsible for their own branch/directory management
- All other phases run normally
- Can be combined with other flags (`--lite`, `--local`, `--resume`)
