# Memory Index

- [Signal abort-unwind check](feedback_signal-abort-unwind-check.md) — when a complete-signal is narrowed to success-only, verify reversible-effect consumers still have an abort recovery path; also check debounce wording for the same "completes"-only trap
- [Directional asymmetry check](feedback_directional-asymmetry-check.md) — bidirectional transitions (e.g. enter/exit) worded around one direction's mechanics (load) may silently omit the reverse direction's failure mode (unload)
- [Scene/World Management review history](project_scene-world-management-review-history.md) — recurring defect pattern across 4 review cycles: fixing one abort-trap opens a mirror-image trap elsewhere; re-review #3 found a debounce-wording propagation miss + a new directional-asymmetry gap
