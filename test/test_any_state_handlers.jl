using Test
using Hsm

@testset "Any State Handlers" begin
    @testset "@on_entry with ::Any state type" begin
        # Create a state machine for testing Any state handlers
        @hsmdef mutable struct AnyStateTestSm
            log::Vector{String}
            data::Dict{Symbol,Any}
        end

        # Define ancestry for testing
        @ancestor AnyStateTestSm begin
            :State_A => :Root
            :State_B => :Root
            :State_A1 => :State_A
            :State_A2 => :State_A
        end

        # Define on_initial handler for non-leaf state State_A
        @on_initial function (sm::AnyStateTestSm, ::State_A)
            return Hsm.transition!(sm, :State_A1) do
                push!(sm.log, "Initial transition to State_A1")
            end
        end

        # Define an on_entry handler that applies to any state
        @on_entry function (sm::AnyStateTestSm, state::Any)
            push!(sm.log, "Generic entry handler for $state")
            sm.data[:last_entered] = state
        end

        # Define a specific handler for one state that should override the generic one
        @on_entry function (sm::AnyStateTestSm, ::State_A1)
            push!(sm.log, "Specific entry handler for State_A1")
            sm.data[:last_entered] = :State_A1_specific
        end

        # Create an instance
        sm = AnyStateTestSm(String[], Dict{Symbol,Any}())

        # Test transition to State_B (should use generic handler)
        Hsm.transition!(sm, :State_B)
        @test sm.log[end] == "Generic entry handler for State_B"
        @test sm.data[:last_entered] == :State_B

        # Test transition to State_A (should use generic handler)
        # Since State_A has an @on_initial handler that automatically transitions to State_A1,
        # we need to disable automatic transition by directly setting the state
        Hsm.current!(sm, :State_A)
        Hsm.source!(sm, :State_A)
        Hsm.on_entry!(sm, :State_A)
        @test sm.log[end] == "Generic entry handler for State_A"
        @test sm.data[:last_entered] == :State_A

        # Test transition to State_A1 (should use specific handler)
        Hsm.transition!(sm, :State_A1)
        @test sm.log[end] == "Specific entry handler for State_A1"
        @test sm.data[:last_entered] == :State_A1_specific
    end

    @testset "@on_exit with ::Any state type" begin
        # Create a state machine for testing Any state handlers
        @hsmdef mutable struct AnyExitStateTestSm
            log::Vector{String}
            data::Dict{Symbol,Any}
        end

        # Define ancestry for testing
        @ancestor AnyExitStateTestSm begin
            :State_X => :Root
            :State_Y => :Root
            :State_X1 => :State_X
            :State_X2 => :State_X
        end

        @on_initial function (sm::AnyExitStateTestSm, ::Root)
            return Hsm.transition!(sm, :State_X) do
                push!(sm.log, "Initial transition to State_X")
            end
        end

        # Define an on_exit handler that applies to any state
        @on_exit function (sm::AnyExitStateTestSm, state::Any)
            state_sym = Symbol(state)
            push!(sm.log, "Generic exit handler for $state_sym")
            sm.data[:last_exited] = state_sym
        end

        @on_initial function (sm::AnyExitStateTestSm, ::State_X)
            return Hsm.transition!(sm, :State_X1) do
                push!(sm.log, "Initial transition to State_X1")
            end
        end

        # Define a specific handler for one state that should override the generic one
        @on_exit function (sm::AnyExitStateTestSm, ::State_X1)
            push!(sm.log, "Specific exit handler for State_X1")
            sm.data[:last_exited] = :State_X1_specific
        end

        # Create an instance and initialize it
        sm = AnyExitStateTestSm(String[], Dict{Symbol,Any}())

        # Set initial state to X
        Hsm.transition!(sm, :State_X)

        # Clear log after initial setup
        empty!(sm.log)

        # Test transition from State_X to State_Y (should use generic handler for State_X)
        Hsm.transition!(sm, :State_Y)
        @test sm.log[end] == "Generic exit handler for State_X"
        @test sm.data[:last_exited] == :State_X

        # Test transition to State_X1
        Hsm.transition!(sm, :State_X1)
        empty!(sm.log)

        # Test transition from State_X1 to State_Y (should call both exit handlers in order)
        # First for State_X1, then for parent State_X
        Hsm.transition!(sm, :State_Y)
        # Check that first we exited State_X1
        @test sm.log[1] == "Specific exit handler for State_X1"
        # Then we should have exited State_X
        @test sm.log[2] == "Generic exit handler for State_X"
        # Last handler should be the one from the parent state
        @test sm.data[:last_exited] == :State_X

        # Test transition back to State_X1 then to State_X2 (should exit State_X1 but not State_X)
        Hsm.transition!(sm, :State_X1)
        empty!(sm.log)
        Hsm.transition!(sm, :State_X2)
        # Check that we exited State_X1 but not State_X (which is the common parent)
        @test sm.log[1] == "Specific exit handler for State_X1"
        @test length(sm.log) == 1 # Only one exit handler should be called
        @test sm.data[:last_exited] == :State_X1_specific
    end

    @testset "Any handlers precedence" begin
        # Create a state machine for testing handler precedence
        @hsmdef mutable struct PrecedenceTestSm
            log::Vector{String}
        end

        # Define ancestry for testing
        @ancestor PrecedenceTestSm begin
            :State_P => :Root
            :State_P1 => :State_P
            :State_P2 => :State_P
        end

        @on_initial function (sm::PrecedenceTestSm, ::Root)
            return Hsm.transition!(sm, :State_P) do
                push!(sm.log, "Initial transition to State_P")
            end
        end

        # Define on_initial handler for non-leaf state State_P
        @on_initial function (sm::PrecedenceTestSm, ::State_P)
            return Hsm.transition!(sm, :State_P1) do
                push!(sm.log, "Initial transition to State_P1")
            end
        end

        # Define handlers with different scopes to test precedence
        @on_entry function (sm::PrecedenceTestSm, state::Any)
            push!(sm.log, "Generic handler $(Symbol(state))")
        end

        @on_entry function (sm::PrecedenceTestSm, ::State_P)
            push!(sm.log, "P handler")
        end

        @on_entry function (sm::PrecedenceTestSm, ::State_P1)
            push!(sm.log, "P1 handler")
        end

        # Create an instance
        sm = PrecedenceTestSm(String[])

        # Test transition to State_P (should use P handler, not generic)
        # Since State_P has an @on_initial handler that automatically transitions to State_P1,
        # we need to disable automatic transition by directly setting the state
        Hsm.current!(sm, :State_P)
        Hsm.source!(sm, :State_P)
        Hsm.on_entry!(sm, :State_P)
        @test sm.log[end] == "P handler"

        # Test transition to State_P1 (should use P1 handler)
        Hsm.transition!(sm, :State_P1)
        @test sm.log[end] == "P1 handler"

        # Test transition to State_P2 (should use generic handler since no specific handler exists)
        # In a hierarchical state machine, handler inheritance works for event handlers
        # but entry/exit handlers are typically called directly for each state in the path
        Hsm.transition!(sm, :State_P2)
        @test sm.log[end] == "Generic handler State_P2"
    end
end
