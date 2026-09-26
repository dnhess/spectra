# Spectra

Instructions for coding agents working in this repository. The gate below is literal. Prose outside the Constraints section is not enforced.

## Constraints

- must-not-contain: sk-ant-
- must-not-contain: BEGIN RSA PRIVATE KEY
- must-contain: Blackboard

## Run the gate

From the repository root:

```bash
bin/spectra gate .
```

Exit 0 means every rule passed. Exit 1 names the file that broke a rule. Exit 2 means this file has no enforceable rules. The rule file itself is not scanned, so a forbidden string written only as a rule does not fail the tree.
