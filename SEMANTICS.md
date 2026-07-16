# Semantic Requirements and Traceability

This document maps Hsm.jl's executable subset of UML state-machine semantics
to implementation and verification evidence. Semantic authority is
[UML 2.5.1, Clause 14.2](https://www.omg.org/spec/UML/2.5.1/PDF) and
[PSSM 1.0](https://www.omg.org/spec/PSSM/1.0/PDF). Hsm.jl uses one active leaf
in one implicit Region and keeps States and events public as `Symbol`s.

## Requirements

| ID | Requirement | Source | Implementation | Verification | Status |
|---|---|---|---|---|---|
| HSM-RTC-001 | An accepted event completes its exit/effect/entry processing before another event is dispatched; reentrant dispatch and transitions are rejected. | UML 14.2.3.9; PSSM 8.5.2 | transition-phase guards, `dispatch!`, `_begin_transition!` | `test_handler_rules.jl` | Implemented |
| HSM-STATE-001 | Initial activation follows the declared initial path. A Transition exits active States from innermost to outermost, executes its effect, then enters target States from outermost to innermost; this also applies to external self Transitions and ancestor-sourced Transitions. | UML 14.2.3.8 and 14.2.3.9; PSSM 8.5.3 | `_transition_core!`, static state paths, `on_initial!` | `test_state_machine.jl`, `test_static_transitions.jl`, `test_tracing.jl`, `test_type_stability.jl` | Implemented |
| HSM-EVENT-001 | Event dispatch searches from the active leaf toward its ancestors. A specific handler takes precedence over a default handler; an unhandled event leaves the active configuration unchanged. | UML 14.2.3.9; PSSM 8.5.2 | `dispatch!`, ValSplit event boundary, handler registries | `test_state_machine.jl`, `test_default_handlers.jl`, `test_type_stability.jl` | Implemented |
| HSM-EDGE-001 | A handler Transition has a static literal target while the public state/event representation remains `Symbol`. | Project performance contract | handler AST rewrite, `_StatePath`, ValSplit boundaries | `test_static_transitions.jl`, `test_type_stability.jl` | Implemented |
| HSM-HANDLER-001 | Entry and exit Behaviors execute only within an already selected Transition and cannot initiate another Transition. Choice guards and Transition effects likewise cannot start reentrant transition processing or recursive dispatch. | UML 14.2.3.4.3 and 14.2.3.9; PSSM 8.5.3 | handler macro validation and transition-phase guards | `test_handler_rules.jl`, `test_choice.jl` | Implemented |
| HSM-HIST-001 | Deep history restores the former active leaf path; shallow history restores the former direct child and follows its normal initial entry. | PSSM 8.5.7.4 | `transition_history!`, `_history_target`, static history target split | `test_history.jl` | Implemented |
| HSM-HIST-002 | History is recorded independently per owning composite State. With no stored history, an explicit default-history Transition is used when declared; otherwise normal initial entry is used. Incoming and default-edge effects execute in that order before target entry. | PSSM 8.5.7.4 | `@historydef`, `@on_history_default`, `_HistoryDefaultAction` | `test_history.jl`, including independent-owner and default-history cases | Implemented |
| HSM-CHOICE-001 | Choice exits the source, runs its incoming effect, enters the containing State path, then evaluates all outgoing guards. | PSSM 8.5.7.3 | `@choice`, `_execute_static_choice_body!` | `test_choice.jl` ordering and guard tests | Implemented |
| HSM-CHOICE-002 | Choice always has an `else` edge and never becomes a stable active vertex. Only the selected outgoing effect and target entry execute. | UML 14.2; PSSM 8.5.7.3 | choice macro validation, `_choice_target_switch!` | `test_choice.jl` | Implemented |
| HSM-CHOICE-003 | After all guards are evaluated, Hsm.jl selects the first enabled guarded edge in source order. | Project-defined deterministic ChoiceStrategy | generated selector in `_rewrite_choice_macro` | `test_choice.jl` | Implemented deviation |
| HSM-FINAL-001 | A FinalState has no child States or State Behaviors. Entering it clears its Region's history. | UML 14.2; PSSM 8.5.3 and 8.5.5 | `@finaldef`, hierarchy validation, `_enter_final!` | `test_completion.jl` | Implemented |
| HSM-FINAL-002 | A nested FinalState completes its owning composite State; a top-level FinalState completes the machine. A FinalState does not accept events. | PSSM 8.5.5 | `_enter_final!`, lifecycle state, final-aware `dispatch!` | `test_completion.jl` | Implemented |
| HSM-COMP-001 | A simple State completes after synchronous entry, and a completed composite State generates a completion event scoped to that exact State. | PSSM 8.5.5 and 8.5.9 | `_schedule_simple_completion!`, `_schedule_completion!`, `@on_completion` | `test_completion.jl` | Implemented subset |
| HSM-COMP-002 | Pending completion events are processed before a later external event; an unhandled completion event is discarded. | PSSM 8.4 and 8.5.9 | `_drain_completion_events!` | `test_completion.jl` | Implemented |
| HSM-TERM-001 | A terminate target enters any required containing State path, terminates the entire machine without cleanup exits, and permits no later execution. | PSSM 8.5.7.1 | `@terminatedef`, `_enter_terminate!`, lifecycle guards | `test_terminate.jl` | Implemented adaptation |
| HSM-ABSTRACT-001 | States, handlers, and Pseudostate registrations declared for an abstract machine family are inherited by each concrete subtype. Concrete handlers may specialize shared behavior, including for parametric families. | Project API contract | abstract-family registries and generated handler methods | `test_abstract_type.jl`, `test_abstract_features.jl`, `test_super_macro.jl` | Implemented |
| HSM-MACRO-001 | Public macros preserve supported struct, `where`, `@kwdef`, docstring, qualified-import, and lexical-scope forms and reject unsupported or unsafe syntax without partial transformation. | Project API and hygiene contract | macro parsers and scope-aware AST transformations | `test_macros.jl`, `test_macro_expansion.jl`, `test_hsmdef_edge_cases.jl`, `test_handler_rules.jl`, `test_docstrings.jl` | Implemented |
| HSM-TRACE-001 | Tracing observes initialization, dispatch, unhandled events, actions, and exit/effect/entry order without changing machine semantics. | Project observability contract | tracing callbacks around dispatch and transition phases | `test_tracing.jl` | Implemented |
| HSM-PERF-001 | Warmed library-owned handled, ancestor-handled, unhandled, external-self, action, nested-initial, abstract-family, choice, history, completion, and terminate paths infer concrete returns and allocate zero heap bytes when callbacks do not allocate. | Project performance contract | finite value splits and generated static kernels | `test_type_stability.jl`, `test_allocation_tests_alloccheck.jl`, and feature-specific allocation assertions | Implemented |

## Verification matrix

The test suite uses focused feature tests plus representative integration
configurations. It intentionally does not repeat the full Cartesian product of
every feature, inheritance form, and macro spelling.

| Capability | Standalone semantics | Integrated configurations | Performance evidence |
|---|---|---|---|
| Initialization, dispatch, propagation, and Transition ordering | `test_state_machine.jl`, `test_static_transitions.jl`, `test_tracing.jl` | abstract and parametric families in `test_abstract_type.jl` and `test_abstract_features.jl` | `test_type_stability.jl`, `test_allocation_tests_alloccheck.jl` |
| Shallow, deep, default, and independently owned history | `test_history.jl` | abstract-family history in `test_abstract_features.jl` | `test_history.jl`, `test_allocation_tests_alloccheck.jl` |
| Choice strategy, effects, ordering, and reentrancy rejection | `test_choice.jl`, `test_handler_rules.jl` | abstract-family choice in `test_abstract_features.jl` | `test_choice.jl` |
| Final States and completion events | `test_completion.jl` | abstract-family lifecycle in `test_abstract_features.jl` | `test_completion.jl` |
| Terminate Pseudostates | `test_terminate.jl` | abstract-family lifecycle in `test_abstract_features.jl` | `test_terminate.jl` |
| Macro forms, inheritance, hygiene, and diagnostics | `test_macros.jl`, `test_macro_expansion.jl`, `test_handler_rules.jl` | `@kwdef`, docstrings, qualified imports, abstract and parametric families | compile-time behavior; runtime paths are covered above |
| Tracing and runnable examples | `test_tracing.jl`, `test_examples.jl` | examples execute in fresh Julia processes | tracing callbacks are outside the library allocation contract |

## Deliberate adaptations

- PSSM delegates selection among multiple enabled choice edges to a
  `ChoiceStrategy`. Hsm.jl evaluates every guard, then uses the first enabled
  guarded edge in source order for deterministic embedded behavior.
- PSSM has an event pool. With one active Region and no asynchronous
  `doActivity`, Hsm.jl stores one pending completion source and drains it
  synchronously before returning control for another external event. It omits
  creation of completion events that have no registered completion Transition;
  this is observationally equivalent within the supported subset.
- PSSM terminate destroys the execution context Object. Hsm.jl must retain the
  Julia object, so it clears pending completion, stores `current == :Root`,
  marks the lifecycle terminated, and rejects later execution.
- Entry and exit connection-point Pseudostates are distinct from `on_entry!`
  and `on_exit!` State Behaviors. Only the Behaviors are implemented.

## Known gaps and out-of-scope semantics

| Gap | Disposition |
|---|---|
| Junction Pseudostates | Not implemented; use ordinary handler control flow or `@choice` when guards must be evaluated on arrival. |
| Entry/exit connection-point Pseudostates | Not implemented; direct static paths and entry/exit Behaviors cover the current single-Region use cases. |
| Fork, join, and orthogonal Regions | Out of scope because Hsm.jl has one active leaf and one implicit Region. |
| `doActivity` completion | Not implemented; completion support covers synchronous entry and completed implicit Regions. |
| Deferred event pools | Not implemented. Callers own any external event queue. |
| PSSM conformance suite | The local tests are requirement-derived but do not claim full PSSM conformance. |

When semantics change, update the requirement row, implementation link,
verification evidence, and gap disposition in the same change.
