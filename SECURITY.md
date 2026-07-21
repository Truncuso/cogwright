# Security Policy

## Reporting a vulnerability

Please report vulnerabilities privately via
[GitHub Security Advisories](https://github.com/Truncuso/cogwright/security/advisories/new)
rather than public issues. You should get a response within a week.

## Scope & threat model

These plugins run inside Claude Code with real shell access:

- **Skills, hooks, and scripts execute on your machine.** Review what you
  install — especially `hooks/` (they run automatically on harness events) and
  anything invoked by git hooks.
- **No plugin here should ever require or transmit secrets.** A plugin asking
  for API keys outside your own environment configuration is a bug — report it.
- **Prompt-injection surface:** skills instruct a model. A plugin whose
  instructions could cause data exfiltration or destructive commands under
  adversarial repo content is a vulnerability, not a usability issue — report
  it the same way.

## Supply chain

- Vendored files are declared per plugin in `.vendored-allowlist.txt`
  (source + retrieval date) and gated in CI.
- Releases are tagged; install from the marketplace at a tag if you want a
  reviewed snapshot.
