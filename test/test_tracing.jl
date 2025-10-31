using Test
using Hsm

@testset "Tracing Hooks" begin
    # Create a state machine with custom trace hooks that log all calls
    @hsmdef mutable struct TracedSm
        trace_log::Vector{String}
    end

    # Define state hierarchy
    @statedef TracedSm :StateA
    @statedef TracedSm :StateB :StateA
    @statedef TracedSm :StateC :StateA
    @statedef TracedSm :StateD

    # Define handlers
    @on_initial function (sm::TracedSm, ::Root)
        return Hsm.transition!(sm, :StateA)
    end

    @on_initial function (sm::TracedSm, ::StateA)
        return Hsm.transition!(sm, :StateB)
    end

    @on_entry function (sm::TracedSm, ::StateA)
        push!(sm.trace_log, "on_entry: StateA")
    end

    @on_entry function (sm::TracedSm, ::StateB)
        push!(sm.trace_log, "on_entry: StateB")
    end

    @on_entry function (sm::TracedSm, ::StateC)
        push!(sm.trace_log, "on_entry: StateC")
    end

    @on_entry function (sm::TracedSm, ::StateD)
        push!(sm.trace_log, "on_entry: StateD")
    end

    @on_exit function (sm::TracedSm, ::StateA)
        push!(sm.trace_log, "on_exit: StateA")
    end

    @on_exit function (sm::TracedSm, ::StateB)
        push!(sm.trace_log, "on_exit: StateB")
    end

    @on_exit function (sm::TracedSm, ::StateC)
        push!(sm.trace_log, "on_exit: StateC")
    end

    @on_event function (sm::TracedSm, ::StateB, ::EventX)
        return Hsm.transition!(sm, :StateC)
    end

    @on_event function (sm::TracedSm, ::StateC, ::EventY)
        return Hsm.transition!(sm, :StateD)
    end

    # Override trace hooks to log their calls
    Hsm.trace_entry(sm::TracedSm, state::Symbol) = push!(sm.trace_log, "trace_entry: $state")
    Hsm.trace_exit(sm::TracedSm, state::Symbol) = push!(sm.trace_log, "trace_exit: $state")
    Hsm.trace_initial(sm::TracedSm, state::Symbol) = push!(sm.trace_log, "trace_initial: $state")

    Hsm.trace_dispatch_start(sm::TracedSm, event::Symbol, arg) =
        push!(sm.trace_log, "trace_dispatch_start: $event")

    Hsm.trace_dispatch_attempt(sm::TracedSm, state::Symbol, event::Symbol) =
        push!(sm.trace_log, "trace_dispatch_attempt: $state, $event")

    Hsm.trace_dispatch_result(sm::TracedSm, state::Symbol, event::Symbol, result) =
        push!(sm.trace_log, "trace_dispatch_result: $state, $event, $result")

    Hsm.trace_transition_begin(sm::TracedSm, current::Symbol, target::Symbol, lca::Symbol) =
        push!(sm.trace_log, "trace_transition_begin: $current -> $target (lca: $lca)")

    Hsm.trace_transition_action(sm::TracedSm, current::Symbol, target::Symbol) =
        push!(sm.trace_log, "trace_transition_action: $current -> $target")

    Hsm.trace_transition_end(sm::TracedSm, current::Symbol, target::Symbol) =
        push!(sm.trace_log, "trace_transition_end: $current -> $target")

    @testset "Initial transition tracing" begin
        sm = TracedSm(String[])

        # Verify trace hooks were called during initialization
        @test "trace_transition_begin: Root -> StateA (lca: Root)" in sm.trace_log
        @test "trace_entry: StateA" in sm.trace_log
        @test "on_entry: StateA" in sm.trace_log
        @test "trace_initial: StateA" in sm.trace_log
        @test "trace_transition_begin: StateA -> StateB (lca: StateA)" in sm.trace_log
        @test "trace_entry: StateB" in sm.trace_log
        @test "on_entry: StateB" in sm.trace_log
        @test "trace_transition_end: StateA -> StateB" in sm.trace_log
        @test "trace_transition_end: Root -> StateA" in sm.trace_log

        # Verify order: trace_entry should come before on_entry
        entry_a_idx = findfirst(==("trace_entry: StateA"), sm.trace_log)
        on_entry_a_idx = findfirst(==("on_entry: StateA"), sm.trace_log)
        @test entry_a_idx < on_entry_a_idx

        entry_b_idx = findfirst(==("trace_entry: StateB"), sm.trace_log)
        on_entry_b_idx = findfirst(==("on_entry: StateB"), sm.trace_log)
        @test entry_b_idx < on_entry_b_idx
    end

    @testset "Event dispatch tracing" begin
        sm = TracedSm(String[])
        empty!(sm.trace_log)  # Clear initialization traces

        # Dispatch event that triggers a transition
        result = Hsm.dispatch!(sm, :EventX)

        @test result === Hsm.EventHandled
        @test "trace_dispatch_start: EventX" in sm.trace_log
        @test "trace_dispatch_attempt: StateB, EventX" in sm.trace_log
        @test "trace_dispatch_result: StateB, EventX, EventHandled" in sm.trace_log

        # Verify dispatch_start comes first
        start_idx = findfirst(==("trace_dispatch_start: EventX"), sm.trace_log)
        attempt_idx = findfirst(==("trace_dispatch_attempt: StateB, EventX"), sm.trace_log)
        result_idx = findfirst(==("trace_dispatch_result: StateB, EventX, EventHandled"), sm.trace_log)
        @test start_idx < attempt_idx < result_idx
    end

    @testset "Transition exit/entry tracing order" begin
        sm = TracedSm(String[])
        empty!(sm.trace_log)

        # Transition from StateB to StateC (both children of StateA)
        Hsm.transition!(sm, :StateC)

        # Verify exit happens before entry
        exit_b_idx = findfirst(==("trace_exit: StateB"), sm.trace_log)
        entry_c_idx = findfirst(==("trace_entry: StateC"), sm.trace_log)
        @test exit_b_idx < entry_c_idx

        # Verify trace_exit comes before on_exit
        trace_exit_idx = findfirst(==("trace_exit: StateB"), sm.trace_log)
        on_exit_idx = findfirst(==("on_exit: StateB"), sm.trace_log)
        @test trace_exit_idx < on_exit_idx

        # Verify transition_begin comes first, transition_end comes last
        begin_idx = findfirst(==("trace_transition_begin: StateB -> StateC (lca: StateA)"), sm.trace_log)
        end_idx = findfirst(==("trace_transition_end: StateB -> StateC"), sm.trace_log)
        @test begin_idx == 1
        @test end_idx == length(sm.trace_log)
    end

    @testset "Transition across hierarchy levels" begin
        sm = TracedSm(String[])
        Hsm.transition!(sm, :StateC)
        empty!(sm.trace_log)

        # Transition from StateC to StateD (different top-level states)
        result = Hsm.dispatch!(sm, :EventY)

        @test result === Hsm.EventHandled

        # Should exit StateC and StateA, then enter StateD
        @test "trace_exit: StateC" in sm.trace_log
        @test "trace_exit: StateA" in sm.trace_log
        @test "trace_entry: StateD" in sm.trace_log

        # Verify order: exit child before parent
        exit_c_idx = findfirst(==("trace_exit: StateC"), sm.trace_log)
        exit_a_idx = findfirst(==("trace_exit: StateA"), sm.trace_log)
        entry_d_idx = findfirst(==("trace_entry: StateD"), sm.trace_log)
        @test exit_c_idx < exit_a_idx < entry_d_idx
    end

    @testset "Unhandled event tracing" begin
        sm = TracedSm(String[])
        empty!(sm.trace_log)

        # Dispatch event that no handler exists for
        result = Hsm.dispatch!(sm, :EventZ)

        @test result === Hsm.EventNotHandled
        @test "trace_dispatch_start: EventZ" in sm.trace_log

        # Should attempt dispatch at StateB, then StateA, then Root
        @test "trace_dispatch_attempt: StateB, EventZ" in sm.trace_log
        @test "trace_dispatch_result: StateB, EventZ, EventNotHandled" in sm.trace_log
        @test "trace_dispatch_attempt: StateA, EventZ" in sm.trace_log
        @test "trace_dispatch_result: StateA, EventZ, EventNotHandled" in sm.trace_log
        @test "trace_dispatch_attempt: Root, EventZ" in sm.trace_log
        @test "trace_dispatch_result: Root, EventZ, EventNotHandled" in sm.trace_log
    end

    @testset "Trace transition action hook" begin
        sm = TracedSm(String[])
        empty!(sm.trace_log)

        # Use transition with action
        Hsm.transition!(sm, :StateC) do
            push!(sm.trace_log, "transition_action_executed")
        end

        # Verify trace_transition_action is called
        @test "trace_transition_action: StateB -> StateC" in sm.trace_log
        @test "transition_action_executed" in sm.trace_log

        # Verify trace_transition_action comes before the action
        trace_action_idx = findfirst(==("trace_transition_action: StateB -> StateC"), sm.trace_log)
        action_exec_idx = findfirst(==("transition_action_executed"), sm.trace_log)
        @test trace_action_idx < action_exec_idx
    end
end
