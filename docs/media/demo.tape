# Renders docs/media/demo.gif:  vhs docs/media/demo.tape  (run from the repo root)
# Every command is real and runs against a throwaway copy of examples/state.
Output docs/media/demo.gif

Set Shell bash
Set FontSize 15
Set Width 1180
Set Height 700
Set Padding 18
Set TypingSpeed 28ms
Set Theme "Builtin Dark"

Hide
Type "export PS1='$ ' ATLAS_HOME=$(mktemp -d) && export ATLAS_STATE=$ATLAS_HOME/state && cp -R examples/state $ATLAS_STATE && touch $ATLAS_STATE/fleet/*.md && export PATH=$PWD/bin:$PATH && clear"
Enter
Show

Type "# A new Claude Code session starts. The SessionStart hook prints this:"
Enter
Sleep 300ms
Type "session-start.sh"
Enter
Sleep 4.5s

Type "clear"
Enter
Type "# Work finished, so /wrap closes the loop for every other session:"
Enter
Sleep 300ms
Type `worklog.sh add --project pantry --missions unit-conversion-v2 "v0.4 cut: under 1/8 tsp reads 'a pinch'"`
Enter
Sleep 900ms
Type "mission.sh done unit-conversion-v2"
Enter
Sleep 700ms
Type `mission.sh decision unit-conversion-v2 "Round to a pinch, not zero" "Silently dropping salt is worse than imprecise"`
Enter
Sleep 1.5s

Type "# The fleet ledger for a 3-task batch (task | lane | status):"
Enter
Type "grep '^| [a-z]' $ATLAS_STATE/fleet/2026-11-14-docs-sprint.md | cut -d'|' -f2,3,8"
Enter
Sleep 2.5s
Type "# One child sent its evidence; the orchestrator re-ran it before marking it verified:"
Enter
Type "cat $ATLAS_STATE/fleet/2026-11-14-docs-sprint/pantry-readme-report.md"
Enter
Sleep 4s

Type "clear"
Enter
Type "# The next session sees all of it:"
Enter
Type "session-start.sh"
Enter
Sleep 5s
