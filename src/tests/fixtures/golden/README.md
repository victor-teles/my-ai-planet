# Golden world states

Saved worlds (WorldState's own save format) that `tests/test_golden_prompts.gd` builds every AI
request from: a fresh island, a village at year 30, a wrathful god's island at year 60, and a late
dystopia that has met its destiny. They are made deterministically from seeds, years of play and
a few miracles (see `_generate()` in the test).

Regenerate them when the save format changes (the golden tests then fail to load them) or when
you want fresh worlds after big sim changes, from the repository root:

    MYAIPLANET_REGEN_GOLDEN=1 scripts/test.sh golden

Review the diff before committing: the files are only rewritten, never checked against old ones.
