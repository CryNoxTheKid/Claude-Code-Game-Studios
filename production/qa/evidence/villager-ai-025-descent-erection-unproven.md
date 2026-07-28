# villager-ai-025: the plumbing landed, the outcome did not

Third attempt at "A builder always has a way down". What holds and what does not,
kept apart deliberately.

## Proven and landed

- `ScaffoldErectionCoordinator` receives real ticks in the shipped game.
- A single marooned observation never erects anything — the persistence
  discipline that keeps this from repeating the queue flood which starved the
  walls earlier.

Both assertions live in
`neues-spiel/tests/integration/scene_world_management/scaffold_erection_descent_live_test.gd`.

## NOT proven — the payload

A persistently marooned villager does not actually get a descent scaffold
erected. Verbatim from the run:

    line 170: expected a descent scaffold to be planned and erected next to the
    marooned villager's pillar top (1008, 11, 1012) after 3 persistent
    observations

The assertion's own body was lost while splitting the file (a write landed before
the extraction step failed); only its failure message survives, and it is
recorded here rather than reconstructed from memory. Rewriting it from the
intent is the first task of the next attempt — and rewriting is cheap next to
pretending the body was preserved.

## The measurement that looked like success and was not

An earlier run appeared to show more scaffolding and was reported that way. It
was invalid: it predated the `connect_tick` fix, so the trigger was inert and its
numbers came out byte-identical to the baseline. The extra scaffolding in that
frame came from the doorway geometry, not from the descent trigger.

**There is still NO valid post-fix measurement of either lever.** Pre-fix, both
stand:

    CROWN: STALLDIAG room walls villager=(993, 9, 1004) state=5 pending=5
           [(994,6,1004) (994,7,1004) (994,8,1004) (992,7,1002) (992,8,1002)]
           final 24/29 wall cells BUILT
    ROOF:  ROOFDESCENT villager=(994, 10, 1003) state=3
           find_path(villager, settlement_ground=(998, 6, 1002)).size()=0 empty=true
    Telemetry: self_seal_climb=39 marooned_relocation=11

## Why it is being landed as plumbing-only rather than held back

The tick fix it uncovered is worth landing on its own (see
`scaffold_tick_wiring_test.gd`): the same constructor-time clock bug silently
disabled the DISMANTLE coordinator's tick, which meant SC-INV-2's deferred retry
could never fire in the shipped game at all. That is a real defect in already-
committed work, found only because a diagnostic printed
`dismantle_connected=false` on a real boot.

Shipping the trigger as "wired, therefore working" would add another
hosted-but-inert instance while fixing one. It is stated as plumbing.
