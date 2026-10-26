# Review of main — 2026-10-26

## Scope and preserved work

- Source: `bb00ed87a0cd67c65e9198d028c5ff921678f825` (`main`, version 0.3.1).
- Review branch: `review/main-2026-10-26`.
- Review worktree: `/home/dgamroth/workspaces/codex/Hsm.jl-main-review`.
- Original checkout: `/home/dgamroth/workspaces/codex/Hsm.jl`, restored to clean `main`.
- Extension checkpoint: `753d991`, branch `repair/issue-8-orthogonal-regions`,
  worktree `/home/dgamroth/workspaces/codex/Hsm.jl-orthogonal-repair`.
  All six modified files and nine new Region test files were copied and
  verified with SHA-256 against their committed content before restoring main.
  The checkpoint preserves the extension exactly; it does not remediate it.
- The original ignored `Manifest.toml` was preserved. No production code was
  changed by this review.

The review covers all three source files, public interfaces, semantic contracts,
tests, README and committed examples, the compilation workload, dependencies,
and CI. Separate reviewers inspected the complete runtime and macro source;
the primary reviewer inspected their evidence, reran focused reproductions,
and reviewed diagrams and package integration. The orthogonal extension and
its eight previously reported findings are excluded from the main findings.
The transfer checksum manifest is retained in `review/extension-transfer.json`.

The disposition is **13 confirmed defects, one accepted modeling improvement,
and one documentation gap**, all
unfixed. P1 denotes a supported configuration that violates the central
allocation contract; P2 denotes a reproducible functional or validation defect;
P3 denotes missing public help documentation. Confidence is high unless a
specific verification limit is stated below. Test success establishes only the
paths tested; it does not resolve the counterexamples in this report.

## Findings

| ID | Priority | Finding | Reproduction |
|---|---|---|---|
| MAIN-001 | P1 | Julia 1.10 dispatch allocates with the freshly resolved dependency | `allocations.jl` |
| MAIN-002 | P2 | Inner FinalState discards enclosing Region history | `nested_final_history.jl` |
| MAIN-003 | P2 | Initial choice exits and reenters its containing State | `initial_choice_owner.jl` |
| MAIN-004 | P2 | Transition to an active containing State restarts defaults | `ancestor_target.jl` |
| MAIN-005 | P2 | Initial transition can escape its owning State | `initial_escape.jl` |
| MAIN-006 | P2 | Handler argument named `transition!` is rewritten as a library call | `argument_shadow.jl` |
| MAIN-007 | P2 | Short nested functions are rewritten in their enclosing handler scope | `short_functions.jl` |
| MAIN-008 | P2 | `@super` captures caller bindings and changes event data | `super_hygiene.jl` |
| MAIN-009 | P2 | Explicit parametric keyword construction lacks its initialized constructor | `kwdef_parameters.jl` |
| MAIN-010 | P2 | Registration loses machine parameter specificity and `where` scope | `behavior_parameters.jl`, `bounded_parameters.jl` |
| MAIN-011 | P2 | Accepted inner constructors bypass initialization | `inner_constructors.jl` |
| MAIN-012 | P2 | Diagram inventory and effective-machine semantics need reconciliation | `diagram_overrides.jl` |
| MAIN-013 | P2 | Generated diagram vertex names collide with public State Symbols | `diagram_names.jl` |
| MAIN-014 | P2 | README abstract-machine example neither activates nor handles its Truck correctly | `readme_abstract.jl` |
| MAIN-015 | P3 | Five exported bindings lack attached help documentation | `public_docs.jl` |

All reproduction files are in [review/reproductions](review/reproductions).
They assert the required behavior and intentionally fail on the reviewed source
where the defect applies. They are review evidence, not additions to
`test/runtests.jl`. [The runner](review/reproduce.jl) executes each in a separate
Julia process and reports its exit code. Its own successful exit means the run
completed, not that the assertions passed.

### MAIN-001 — Preserve the zero-allocation boundary on Julia 1.10

**Location:** `Project.toml:13` and `src/macros.jl:1032–1167`, reached through
`src/Hsm.jl:2757`. **Contract:** HSM-PERF-001 and the allocation/type-stability
sections of `AGENTS.md`.

**Observed:** a fresh package test environment on Julia 1.10.12 fails 16 existing
allocation or AllocCheck assertions. A smaller fixture first loads the valid
manual machines in `test_core.jl`, then defines an independent macro-generated
machine. Warmed `dispatch!(::AllocationRepro.Machine, ::Symbol, ::Int64)` takes
64 heap bytes in two allocations per handled event. The handler only increments
an `Int` field. Its correctness oracle verifies the result, active leaf, and
counter increment. Construction, setup, printing, and compilation are outside
the measured expression; the concrete call and measurement functions are warmed
ten times. Linux x86_64, one Julia thread, ordinary non-exceptional processing.

The fresh environment resolves ValSplit 0.1.2 with tree
`e00dde2141485abeca9d94c07abbd8f38da5c81d`. The original checkout's ignored
manifest refers to a different tree, `086c4b85e8f1200bef2ce3bf27d26b57b8f091ce`,
also labeled 0.1.2. Their installed source differs in the generated fallback:
the former captures the original arguments in a zero-argument closure. The
original manifest therefore does not establish what an ordinary fresh
installation will do. Julia 1.13.2 with the resolved dependency passes the same
allocation fixture and all existing tests.

**Analysis:** typed-IR and allocation profiling identify the `on_event!` value
split as the allocating boundary. Its internal result becomes `Any` in the
failing case even though public `dispatch!` still infers `EventReturn`. A clean
public `@inferred` assertion alone misses this violation. The full suite also
fails dynamic history, choice, completion, terminate, and other dispatch
allocation checks; the static AllocCheck failures are separate evidence.

**Remediation:** make Hsm's supported Symbol split allocation-free with an
ordinary resolved dependency, or select a verified dependency release and
document the compatibility decision. Preserve source restoration and exception
handling. Do not weaken the zero-byte contract or treat the locally different
dependency tree as a package fix. Verify the full concrete path matrix on Julia
1.10 and current stable, dynamically and with AllocCheck, after the repair.

### MAIN-002 — Keep history for enclosing non-final States

**Location:** `src/Hsm.jl:1812–1818`; related paths at lines 917 and 936.
**Contracts:** HSM-HIST-001/002 and HSM-FINAL-001.

**Observed:** Outer contains Branch; Branch contains Leaf and Finished, a
FinalState. After entering Branch, reaching Finished, and leaving Outer, both
Outer and Branch have `:Root` history. A shallow recall of Outer enters its
ordinary Initial State. It should restore Branch, the non-final direct child
of Outer's Region, and then enter Branch's normal default Leaf.

**Analysis:** each exited history owner is cleared merely because the deepest
active vertex is final. FinalState completion clears its own containing Region,
not every enclosing Region. This follows the direct-ownership rule in
[PSSM 1.0 §8.5.3, printed p.31](https://www.omg.org/spec/PSSM/1.0/PDF).
The reproductions on Julia 1.10.12 and 1.13.2 agree.

**Remediation:** record history independently for each owning Region and retain
enclosing non-final configurations. Verify shallow and deep restoration after
nested completion, including static, direct API, and choice exit paths. The
current final-history tests cover FinalState directly below the history owner.

### MAIN-003 — Preserve an active owner when reaching its initial choice

**Location:** `src/Hsm.jl:2045–2046`. **Contracts:** HSM-STATE-001 and
HSM-CHOICE-001.

**Observed:** constructing a machine whose Owner initial transition reaches
`@choice sm :Owner` produces
`[:enter_owner, :exit_owner, :enter_owner]` before activating A. Owner should
be entered once and should not exit during its own default activation.

**Analysis:** the choice's containing State is used as the transition target in
the ordinary path calculation. Equal source and owner are consequently treated
as an external self transition, although the destination is the choice inside
that owner. The same helper affects an event handler on the choice owner.

**Remediation:** calculate entry/exit paths to the choice location while
preserving an already active owner. Verify both initial and event-source cases,
including order of incoming effect, guard evaluation, and outgoing effect.
Confirmed on Julia 1.10.12 and 1.13.2.

### MAIN-004 — Complete the source Region when targeting its active owner

**Location:** `src/Hsm.jl:991–997` and the unconditional activation at line 1842.
**Contracts:** HSM-STATE-001 and HSM-COMP-001/002 under the stated UML/PSSM
semantic authority.

**Observed:** Leaf → Owner reruns Owner's default transition and ends in Leaf
with log `[:default]`. Owner's completion handler that targets Done never runs.

**Analysis and adjudication:**
[PSSM §8.5.3 and §8.5.8, with test Transition 011-C](https://www.omg.org/spec/PSSM/1.0/PDF)
specify source-Region completion when a transition targets its already active
containing State. The repository's documented topology adaptation covers
composite-to-descendant local transitions and external self transitions; it
does not document restarting the ancestor's default path. This is accepted as
a semantic defect, rather than silently treating the existing reset as the
intended contract. Confirmed on Julia 1.10.12 and 1.13.2.

**Remediation:** distinguish active-ancestor targets from ordinary default
entry, represent Region completion, and schedule its owner's scoped completion
event. Test static and direct API paths, with and without completion handlers.

### MAIN-005 — Validate initial-transition containment

**Location:** `src/Hsm.jl:1316–1324`; documented contract in
`src/macros.jl:1757–1759`. **Contracts:** HSM-STATE-001 and `@on_initial`'s
statically named child target requirement.

**Observed:** Owner's initial handler targets sibling Outside. Construction
accepts the graph, exits Owner during its activation, and returns with
`current == :Outside`. Both Julia 1.10.12 and 1.13.2 accept it.

**Analysis:** the kernel checks that the source is active and uses the normal
transition engine, but does not validate that the initial edge stays inside
the containing State. Registration and static target checking alone are
insufficient topology validation.

**Remediation:** reject self, ancestor, and sibling initial targets before
running their effects or exits. Preserve supported descendant paths and
explicit choice control flow; test the containment rule separately from
single-edge and unguarded-initial validation.

### MAIN-006 — Include handler arguments in binding analysis

**Location:** `src/macros.jl:933–934`. **Contract:** HSM-MACRO-001 and the explicit
rule against rewriting a shadowed local `transition!` binding.

**Observed:** a handler's event-data parameter is named `transition!` and holds
an application callback. Calling it with the usual two arguments is rewritten
into a library transition. The callback runs zero times and the machine moves
from A to B; it should run once and leave A active. This silently changes the
application's behavior rather than reporting a syntax error.

**Analysis:** binding collection examines only the body, omitting the handler
signature. Confirmed independently on Julia 1.10.12, 1.12.7, and 1.13.2.

**Remediation:** pass all handler argument bindings into scope analysis before
rewriting transitions. Cover transition, history, and choice names where local
bindings are legal, including typed and destructured arguments where supported.

### MAIN-007 — Recognize short function definitions as scope boundaries

**Location:** `src/macros.jl:838–839`. **Contract:** HSM-MACRO-001.

**Observed:** a nested `helper(sm) = transition!(sm, :A)` called on another
machine in B is rewritten with the enclosing handler's source A. It throws
“Transition source A is not active below current state B.” The identical
long-form nested function succeeds and changes the second machine to A.
An uncalled short helper inside an entry handler is also wrongly rejected.

**Analysis:** the walker stops at long function definitions and lambdas, but
recurses through short definitions represented by an assignment expression.
Confirmed on Julia 1.10.12, 1.12.7, and 1.13.2.

**Remediation:** identify short function signatures, including supported
`where` forms, before recursing. Do not transform their bodies or classify
their statements as transitions of the enclosing handler.

### MAIN-008 — Generate hygienic locals in `@super`

**Location:** `src/macros.jl:2894–2904`, with the same pattern in the State
Behavior branch. **Contract:** HSM-MACRO-001 and HSM-ABSTRACT-001.

**Observed:** a concrete handler receives event data `123` in a parameter named
`abstract_type` and forwards it through `@super`. The parent receives the
abstract machine type instead of `123`.

**Analysis:** the escaped expansion introduces fixed `let` names, including
`abstract_type`, `state_type`, `event_type`, and `data_type`. These capture
caller references used later in the expansion. Confirmed on Julia 1.10.12,
1.12.7, and 1.13.2.

**Remediation:** use generated local names in both macro branches and qualify
generated Base bindings. Verify values and machine identity with caller names
that collide with each former temporary.

### MAIN-009 — Supply explicit parametric initialized constructors

**Location:** `src/macros.jl:2496–2497`. **Contract:** HSM-MACRO-001 and supported
`Base.@kwdef` integration.

**Observed:** for `@hsmdef Base.@kwdef mutable struct KwParamSm{T}` with an
`x::T` default, `KwParamSm(x=1)` constructs and activates A, but
`KwParamSm{Int}()` throws a MethodError for `KwParamSm{Int64}(::Int64)`.

**Analysis:** Base's preserved explicit keyword constructor calls the
parameterized positional constructor. Hsm only generates the initialized
user-field constructor on the bare type name. Confirmed on Julia 1.10.12,
1.12.7, and 1.13.2.

**Remediation:** retain the type parameter declarations and provide the explicit
parameterized constructor required by Base's keyword expansion. Verify omitted
defaults, specified keywords, type constraints, const fields, and initialization
on both supported-version boundaries.

### MAIN-010 — Preserve machine specialization in metadata registrations

**Location:** `src/macros.jl:1016–1027`; related registration generators start at
lines 956 and 974. **Contracts:** HSM-ABSTRACT-001 and HSM-MACRO-001.

**Observed:** an entry handler for `ParamBehaviorSm{Int}` is registered on bare
`ParamBehaviorSm`. Construction of `ParamBehaviorSm{Float64}`, where A is a
FinalState and that entry method is inapplicable, is incorrectly rejected for
having an entry Behavior. A separate normal handler signature
`sm::M where {M<:WhereFamily}` fails definition with `UndefVarError: M not
defined`, because its generated registration has lost the `where` scope.

**Analysis:** registration methods discard curly type parameters and are
emitted without the handler's complete constraints. Metadata therefore
describes methods that do not apply, or cannot be defined at all. The first
case is confirmed on Julia 1.10.12, 1.12.7, and 1.13.2; the bounded-parameter
case is also confirmed on Julia 1.10.12 and 1.12.7; the primary independently
reproduced it on Julia 1.13.2.

**Remediation:** retain concrete type restrictions and applicable `where`
parameters across behavior, history, and diagram metadata. Validate inherited,
specialized, and bounded machine definitions through construction and use,
not just macro expansion.

### MAIN-011 — Reject unsupported inner constructors before creating invalid machines

**Location:** `src/macros.jl:2788–2800`; private-field insertion starts at line
2394. **Contract:** automatic initialization and HSM-MACRO-001's fail-closed rule.

**Observed:** `InnerSm(value::Int) = new(value)` inside an accepted `@hsmdef`
constructs an object whose user field is valid but whose private State fields
are undefined. `current(sm)` throws UndefRefError; dispatch also reads
uninitialized lifecycle state.

**Analysis:** the inner constructor remains more specific than Hsm's generated
outer constructor and bypasses initialization. The macro currently accepts
this syntax without validating or transforming its construction protocol.
Confirmed on Julia 1.10.12, 1.12.7, and 1.13.2.

**Remediation:** reject inner constructor syntax with a clear error until its
initialization behavior is designed and supported. Supporting arbitrary `new`
calls would require an explicit construction contract and separate tests.

### MAIN-012 — Resolve overridden handlers when discovering diagram edges

**Location:** `src/diagrams.jl:289–299`. **Disposition:** accepted modeling
improvement; reconcile HSM-DIAGRAM-001 and the documented inventory scope with
effective UML-machine semantics.

**Observed:** a family initial handler targets A; its concrete override targets
B. The concrete machine starts in B, but its diagram has both A and B as initial
targets. An overridden event handler similarly retains both its parent's
unreachable edge and the replacement edge. The generated diagram gives a
single initial Pseudostate multiple outgoing edges.

**Analysis and adjudication:** discovery unions inherited registrations without
resolving which handler Julia dispatch selects. README lines 185–192 and the
DiagramModel docstring explicitly promise all registered edges, including
inherited declarations. The output therefore follows that inventory scope;
effective-handler filtering is not already an explicit tooling promise.
Nevertheless, it can misrepresent the concrete UML machine and its initial
Pseudostate. This is retained as an accepted modeling improvement requiring a
contract decision, rather than labeled a violation of an existing filtering
promise. The existing inheritance test has no overrides. Confirmed on Julia
1.12.7 and 1.13.2.

**Remediation:** distinguish a raw declaration inventory from an effective
machine model, document which is rendered, and reconcile the semantic claim.
For an effective model, associate registrations with their declaring handler
and preserve dispatch specificity. Preserve genuine multiple branches inside
the selected handler; do not deduplicate all edges merely by source and trigger.
The fixture expresses the proposed effective-model oracle, subject to that
contract decision.

### MAIN-013 — Separate generated Pseudostate identity from public State names

**Location:** `src/diagrams.jl:75–76`, `346–354`, and initial-edge grouping at
lines 383–402. **Contract:** HSM-DIAGRAM-001 and the public Symbol State API.

**Observed:** a valid State named `:__hsm_initial_Root` collides with the
generated Root initial Pseudostate. Its Go event edge is emitted as
`[*] --> state_1 : Go` instead of an edge from that State. The model also
conflates the initial source and State target into a self edge.

**Analysis:** the public and generated vertices share a Symbol namespace and
alias dictionary. The serializer identifies initial edges by source name, so
the collision changes event topology. No reserved-name restriction is declared
or enforced. Confirmed on Julia 1.13.2.

**Remediation:** allocate collision-free model identifiers or represent vertex
kind and identity separately. Verify initial, history, and choice identifier
collisions in both serializers and preserve every event edge's source.

### MAIN-014 — Make the README abstract-machine example executable

**Location:** `README.md:96–137`, especially line 128. **Contract:** documented
onboarding behavior and the package's automatic-initialization model.

**Observed:** executing the complete Abstract State Machines code block leaves
both vehicles in `:Root` with zero speed: there is no initial handler selecting
Stopped, so Start and Accelerate do not reach the shown handlers. After adding
the missing activation in a diagnostic follow-up, Truck's acceleration handler
throws because it writes `fuel`, a field that Truck does not have.

**Remediation:** declare the family initial path and make the Truck fields and
handler agree. Add a correctness oracle for this README block, including State,
speed, and fuel/cargo behavior; the committed example smoke tests exercise
different files. Confirmed on Julia 1.13.2.

### MAIN-015 — Attach documentation to exported constants and exception types

**Location:** exports in `src/Hsm.jl:8,21`; exception types at
`src/macros.jl:2–14`.

**Observed:** Julia's attached-documentation inventory reports no documentation
for EventHandled, EventNotHandled, HsmEventError, HsmMacroError, and HsmStateError.
Their meanings appear in other documentation, but help on these exported
bindings lacks the package contract. Confirmed with `Base.Docs.hasdoc` on
Julia 1.13.2.

**Remediation:** attach concise documentation describing return/propagation
semantics and exception construction or conditions. This is a documentation
gap; it does not cause the runtime failures above.

## Verification evidence and limits

| Check | Evidence | Result |
|---|---|---|
| Full existing suite, Julia 1.13.3 | Fresh `Pkg.test(; allow_reresolve=false)` in this worktree | 837 passed |
| Full existing suite, Julia 1.13.2 | Fresh `Pkg.test(; allow_reresolve=false)` in this worktree | 837 passed |
| Full existing suite, Julia 1.10.12 | Same source SHA in isolated HEAD snapshot `/tmp/hsm-head-review.7MRxPy`; evidence reused from the immediately preceding diff review | 821 passed, 16 allocation/AllocCheck failures |
| Runtime repros MAIN-002 through MAIN-005 | Separate source reviewer; public macros/API; Julia 1.10.12 and 1.13.2 | Same incorrect behavior on both versions |
| Macro repros MAIN-006 through MAIN-011 | Separate source reviewer; Julia 1.10.12 and 1.12.7; primary independently ran Julia 1.13.2 | Reproduced; exact assertions retained in review files |
| MAIN-001 allocation fixture | Julia 1.10.12, x86_64 Linux, one thread, resolved ValSplit tree `e00dde2…` | 64 bytes, two allocations per warmed handled event |
| MAIN-001 allocation fixture | Julia 1.13.2, same platform and dependency tree | Zero bytes and zero allocations |
| Diagram, README, public-doc repros | Primary reviewer, Julia 1.13.2 | Counterexamples reproduced |
| Source formatting integrity | `git diff --check` | No whitespace errors |

Julia 1.13.3 was the latest stable patch at review time, confirmed against the
[official release](https://github.com/JuliaLang/julia/releases/tag/v1.13.3).
The full suite passed all 837 tests on 1.13.3. All 15 functional/macro/diagram/
documentation reproduction scripts failed their expected behavior assertions;
the allocation script passed on this version. MAIN-010 has two scripts, so this
is 16 scripts for 15 findings. Results are retained in [review/results](review/results); stored log trailing
whitespace is normalized without changing diagnostic content.
The primary reran the fixtures in isolated child processes on 1.13.3.

Historical CI is separate evidence: the
[historical run for the exact source commit](https://github.com/DarrylGamroth/Hsm.jl/actions/runs/30610307205)
passed its six stable/minimum-version platform jobs and both pinned renderer
jobs. Its three nightly jobs failed and were allowed failures. This historical
result does not establish the behavior of today's resolved dependencies.
Windows and macOS were not rerun locally. The pinned PlantUML and Mermaid
containers were not rerun locally; serializer counterexamples above are
observable directly in the generated model/text and do not depend on renderer
behavior. No hardware behavior is claimed by this software review.

The package uses a declared runtime dependency, ValSplit, and keeps Test,
MacroTools, and AllocCheck in the test target. No new QA or runtime dependency
was added. No format-wide cleanup or production remediation was performed.

## Disposition and follow-up boundary

The 13 defect findings are accepted and open; MAIN-012 is an accepted modeling
improvement requiring a tooling contract decision, and MAIN-015 is an open
documentation gap. Correctness repairs must make the associated fixture pass
on Julia 1.10 and current stable while retaining the existing ordering,
allocation, and macro-hygiene checks. MAIN-011's oracle explicitly expects a
clear macro-expansion rejection, matching its proposed fail-closed remedy;
MAIN-005 expects construction to reject the escaping initial edge. MAIN-012's
effective-model fixture is conditional on the clarified tooling contract.
Updates to semantic behavior or promoted claims must also reconcile the
affected `SEMANTICS.md` rows. The current “Implemented” statuses there should
be read with the exceptions established in this review, rather than as evidence
that these counterexamples passed.

The earlier extension review is preserved by its checkpoint and this scope
record. Its deferred issues are: inactive Region after ancestor target;
unvalidated cross-Region history; continued activation after initial terminate;
named Region argument lowering; lost event-data overload dispatch; incorrect
compatibility `current`; absolute-depth arbitration across unrelated branches;
and missing Region-aware diagram integration. MAIN-004 additionally establishes
that the eventual ancestor-target repair should use the authoritative Region
completion semantics, rather than merely copying main's existing default restart.


Independent final review checked the macro findings, diagram and README
counterexamples, and consistency between remedies and regression oracles.
It led to the MAIN-011 rejection oracle, correction of the MAIN-005 diagnostic
setup, and explicit adjudication of MAIN-012's documented inventory scope.
