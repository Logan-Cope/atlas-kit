# Fleet 2026-11-14-docs-sprint

Orchestrator: session fleet-orchestrator-7c. Asked for by: the owner, "bring every README up to the same quickstart standard".

| Task | Lane | Model | Owns | Done when | Session | Status | Evidence |
|---|---|---|---|---|---|---|---|
| pantry-readme | Local | claude-sonnet-5-5 | ~/code/pantry/README.md | quickstart runs on a clean clone in under 5 min; lychee 0 broken links | 3f2a9c1e | done (verified) | clean clone ran in 2m40s (re-run by orchestrator); lychee 14 OK, 0 errors |
| trailmap-readme | Local | claude-sonnet-5-5 | ~/code/trailmap/README.md, ~/code/trailmap/docs/ | same, plus every CLI flag in the README exists in --help | 8b41d07a | running | sent back once: README listed --units, --help has no such flag |
| field-notes-readme | Cloud | claude-sonnet-5-5 | field-notes repo, PR only | PR open with green CI; build of the site passes | c90e55b2 | running | |
