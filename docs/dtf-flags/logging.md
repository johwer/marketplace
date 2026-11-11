# DTF: logging tickets (Phase 4.5 testing)

Read when Suki tests a ticket whose change is about logging.

- **Verify through the real pipeline, not a unit test of the logger.** Clone the worktree service container from `docker inspect` env with ONE override (e.g. the vendor API URL → a host stub), assert on `docker logs`, and grep the logs for the stub's sentinel values to prove nothing leaks. Delete the env file afterwards — it holds the container's secrets.
