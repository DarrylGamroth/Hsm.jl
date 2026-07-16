# Hsm.jl Agent Guidance

## Scope and semantic authority

- This file applies to the entire repository.
- Hsm.jl models UML behavior state machines. Use UML 2.5.1, especially Clause 14.2, as the semantic authority: <https://www.omg.org/spec/UML/2.5.1/PDF>.
- Use PSSM 1.0 for precise execution semantics, especially transition firing, state activation, run-to-completion, and history restoration: <https://www.omg.org/spec/PSSM/1.0/PDF>.
- Do not infer intended semantics from behavior that merely happens to be possible in the current implementation. Document and test any deliberate deviation from UML/PSSM.
- Keep `SEMANTICS.md` synchronized with implementation, verification evidence, deliberate adaptations, and known gaps.

## State-machine execution rules

- Preserve run-to-completion semantics. A dispatched event selects and completes its transition processing before another event is handled.
- Do not permit a state machine to start a reentrant transition while an existing transition is executing.
- Preserve transition firing order: exit active states from innermost to outermost, execute the transition effect, then enter target states from outermost to innermost.
- `transition!` is library-owned behavior and is not an extension point. Never overload it for state-machine-specific behavior.
- Ordinary transition edges are static. Runtime logic may choose among statically named edges, but handler code must not compute an arbitrary runtime target.
- Keep states and events represented publicly as `Symbol`s. Use finite value splitting where runtime `Symbol` values must select statically specialized code; do not replace mixed event streams with type-based dynamic dispatch.

## Handler semantics

- `@on_event` handles a dispatched event and may select a transition whose target is statically named.
- `@on_initial` represents default activation through an initial Pseudostate. Under UML, an initial Pseudostate has at most one outgoing Transition, with no trigger or guard. Do not add conditional initial-transition semantics without explicitly modeling and documenting a UML choice/junction extension.
- `@on_entry` represents a State entry Behavior. It executes as part of an already selected transition and must not initiate another transition.
- `@on_exit` represents a State exit Behavior. It executes as part of an already selected transition and must not initiate another transition.
- Handler macros should reject direct `transition!` calls in `@on_entry` and `@on_exit`. Such calls must not silently use either the static or dynamic transition implementation.
- If an entry or exit Behavior emits an event, that event belongs to later run-to-completion processing; it must not cause reentrant traversal.
- A transition `do` block is the transition effect Behavior and belongs between exit and entry processing.

## History semantics

- Model history explicitly as a history Pseudostate operation, such as `transition_history!`; do not overload or reinterpret ordinary `transition!`.
- Support shallow and deep history as distinct, statically known modes.
- Hsm.jl currently has one active leaf and no orthogonal Regions. Treat each composite State as having one implicit Region when mapping UML history semantics.
- Record history per history-owning composite State when its active configuration is exited.
- Deep history restores the complete previously active ancestry path and executes entry Behaviors from outermost to innermost. It must not replay unrelated transition effects or default initial transitions along the restored path.
- Shallow history restores only the previously active direct child, then applies that child's normal default-entry behavior.
- If no history exists, take a declared default-history Transition when available; otherwise use the Region's normal default entry.
- Keep the history owner and history kind static. Split the remembered runtime `Symbol` over the finite set of valid descendants and reuse statically specialized entry paths.
- History support must remain type-stable and allocation-free in steady-state transition processing. Per-instance initialization may allocate explicitly documented history storage.

## Choice, completion, final, and terminate semantics

- Pseudostates are transient control vertices. A run-to-completion step must not finish with a choice, history, initial, or terminate Pseudostate as the active `current` State.
- A choice is reached only through `@choice`. Exit the source path, execute the incoming effect, enter the choice's containing State path, evaluate every outgoing guard, select an enabled edge, execute only that edge's effect, and enter its target.
- Require an `else` edge for every choice. Hsm.jl deliberately uses the first enabled guarded edge in source order after evaluating all guards; this is its deterministic `ChoiceStrategy` in place of PSSM's nondeterministic strategy hook.
- Choice owners and targets are static literal `Symbol`s. Guards may inspect runtime data but must not initiate transitions or dispatch recursively.
- A FinalState has no State Behaviors or child States. Entering it completes its implicit Region and clears that Region's history.
- A nested FinalState schedules a completion event for its owning composite State. A top-level FinalState marks the whole machine complete.
- Completion events are scoped to the State that completed and are processed before a later external event. A completion handler may select at most one static Transition.
- A FinalState does not accept events. While its owning composite awaits an event, dispatch continues at that owner.
- A terminate Pseudostate has no State Behaviors or child States. Its incoming compound Transition enters any required containing States, then terminates the entire machine without running exit Behaviors for the active configuration.
- A terminated machine must reject further dispatches and transitions. The Julia object remains available for lifecycle inspection even though PSSM models destruction of the execution context.
- Hsm.jl currently supports one implicit Region. Junctions, entry/exit connection-point Pseudostates, fork/join, orthogonal Regions, `doActivity`, and deferred-event semantics are out of scope unless separately designed and documented.

## Macro implementation rules

- AST transformations must be scope-aware. Do not rewrite inside nested functions, lambdas, quoted code, or unrelated macro arguments, and do not rewrite a shadowed local binding merely because its name is `transition!`.
- Qualify generated references to Hsm and Base bindings. Macro use through `import Hsm; Hsm.@macro ...` must not require callers to import implementation dependencies such as ValSplit.
- Parse every `where` parameter and reject unsupported signatures or surplus handler arguments clearly; never silently drop syntax.
- Retain `Base.@kwdef` integration because it is a supported and useful pattern. Isolate assumptions about its expanded AST, test them on every supported Julia version, and fail clearly if the expansion is no longer recognized.
- Fail closed when a macro cannot safely understand its input rather than returning a partially transformed definition.

## Compatibility, performance, and verification

- Support Julia 1.10 and newer only.
- Separate steady-state runtime benchmarks from package-load, precompile, and first-call latency measurements.
- Test semantic changes on Julia 1.10 and the current stable Julia release.
- Keep committed examples runnable with `julia --project=.` on Julia 1.10 and
  current stable. Examples may use Hsm.jl and standard libraries; keep Revise,
  BenchmarkTools, and other personal tools in developer environments.
- Add tests for transition ordering, ancestor-handled events, self transitions, initial activation, forbidden entry/exit transitions, macro hygiene, and shallow/deep/default history behavior as applicable.
- State machines defined by downstream packages may use deterministic `PrecompileTools` workloads after all states and handlers are declared. Do not add broad automatic precompile workloads that compile unknown downstream machines or inflate cache size without measurement.

## Steady-state allocation contract

- The library-owned portions of warmed `dispatch!` and transition paths have a budget of zero heap bytes for concrete argument types when user handlers, transition effects, and tracing callbacks are themselves allocation-free.
- The contract covers handled leaf events, ancestor propagation and handling, unhandled events, external self transitions, transitions with an action, nested initial activation, and shallow/deep/default-history paths when implemented.
- Compilation, precompilation, state-machine construction, explicitly documented history-storage initialization, exception construction and throwing, logging, and allocations performed by user callbacks are outside the steady-state contract.
- The library must not allocate merely to invoke or pass through a user callback. Preserve its concrete callable type through hot code, for example with `where {F<:Function}`, when measurement shows Julia would otherwise avoid specialization.
- Warm the exact concrete signature before measuring. Measure behind a function barrier and prepare or reset mutated machine state outside the measured expression using the same amortization boundary available to production callers.
- Use dynamic `@allocated` regression tests and AllocCheck as separate evidence. Neither replaces the other; document concrete signatures, aliasing assumptions, and whether exceptional paths are included in each check.
- Do not remove required cleanup, synchronization, logging, or error handling solely to satisfy an allocation assertion. In particular, preserve `dispatch!` source restoration through `try`/`finally`; document the acknowledged Julia/Windows exception-frame allocation separately as a platform/runtime limitation.

## Type-stability contract

- Representative concrete calls to public hot entry points must infer a concrete return type, verified with `@inferred` or equivalent typed-IR inspection.
- Investigate `Any`, abstract values, and runtime dispatch when they reach repeated hot operations. A generic method signature or a small concrete union is not by itself a type-instability defect.
- Keep internal fields and hot-path containers concrete. Do not introduce `Function` fields, `Vector{Any}`, or other abstract storage into dispatch, transition, or history state.
- Keep the intentionally dynamic `Symbol` event boundary outside the specialized kernels. Split finite registered values once, then enter type-stable code.
- Internal zero-field path types may encode the ancestry of a statically named state while the public state remains a `Symbol`. Keep specialization proportional to the paths and reachable active configurations used by an edge; do not carry the entire machine graph through every edge specialization.
- Preserve intentional dynamic boundaries when required for extensibility, but isolate them with a function barrier and document them.
- Keep JET and Cthulhu in a developer or test environment rather than runtime dependencies unless package functionality explicitly requires them. Treat a clean report as evidence only for the concrete call graph analyzed.
- Do not add `Val`, generated functions, type assertions, forced specialization, or `@inline` solely to silence inference output. Require measured steady-state benefit and assess first-call latency, invalidations, native-code size, and precompile-cache growth.

## Performance regression evidence

- Allocation and inference fixtures must preserve a correctness oracle and exercise the same semantic path before and after a change.
- Record Julia version, platform, thread count, concrete call signature, warmup boundary, bytes, allocation count, and timing for performance claims.
- For mutating transitions, use controlled setup with one transition per benchmark evaluation or a representative cycle whose state evolution is part of the workload.
- At minimum, maintain performance coverage for handled, ancestor-handled, unhandled, self-transition, action, and initial-transition paths; extend the matrix for each history mode, choice, completion, FinalState, and terminate paths.
- Report compile-time or code-size regressions alongside runtime improvements when increasing specialization or generating code per state or transition edge.
