# Agent instructions

- Read README.md and docs/resource-registry.md before changes.
- Keep credentials, private service configuration, user logs and generated artifacts out of Git.
- Use dev for daily integration and main for stable releases. Ordinary development does not authorize pushing main, creating tags or publishing releases.
- MCP mutation targets must be unambiguous. Use stable IDs and display the full project / environment / service path.
- Manage only processes owned by the application; never stop unrelated processes solely by name or port.
- Confirm the implementation stack before adding application code or dependencies.
