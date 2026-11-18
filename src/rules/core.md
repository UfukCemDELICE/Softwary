# softwary rules

These rules hold in every session. Details come from skills when they are needed.

1. Do not write code without an approved spec and slice.
2. Do not declare work done without showing the output of `./softwary verify`.
3. Never weaken tests, gates or configuration. The loop never touches the protected paths (`.softwary/`, `.github/`, `CODEOWNERS`, `docs/CODEOWNERS`, `softwary`, `product/`, `architecture/model/`, `architecture/data/`, `architecture/contracts/`, `architecture/proofs/`, `architecture/drift.md`). Under `architecture/formal/` only a record's invariants and findings and the set of files (adding, deleting, renaming) are protected; the models, their configurations and the rest of a record are the loop's own, and `./softwary formal verified` rules on them.
4. Change the architecture model and contracts only in the `blueprint` stage.
5. Never edit generated files by hand; change the source and run `./softwary sync`.
6. When something is unclear, ask instead of assuming.
7. Do not read or commit files that contain secrets.
8. Only a human runs `./softwary approve`: it records the approval of the product or the blueprint, and an agent never runs it.
