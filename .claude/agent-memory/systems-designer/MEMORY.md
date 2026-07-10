# Memory Index

- [Signal abort-unwind check](feedback_signal-abort-unwind-check.md) — when a complete-signal is narrowed to success-only, verify reversible-effect consumers still have an abort recovery path; also check debounce wording for the same "completes"-only trap
- [Directional asymmetry check](feedback_directional-asymmetry-check.md) — bidirectional transitions (e.g. enter/exit) worded around one direction's mechanics (load) may silently omit the reverse direction's failure mode (unload)
- [Scene/World Management review history](project_scene-world-management-review-history.md) — recurring defect pattern across 4 review cycles: fixing one abort-trap opens a mirror-image trap elsewhere; re-review #3 found a debounce-wording propagation miss + a new directional-asymmetry gap
- [Schema enforcement gap check](feedback_schema-enforcement-gap-check.md) — declared schema constraints (type/range/conditional) need a matching entry in the validation checklist AND an AC, or they're decorative; also: a "warning" that fires on every valid instance of a class isn't a warning
- [Dependency table completeness check](feedback_dependency-table-completeness-check.md) — grep sibling GDDs for references to the target system rather than trusting its own Dependencies table; catches missing rows, inconsistent "shared vocabulary" treatment, and stale "Undesigned" markers
