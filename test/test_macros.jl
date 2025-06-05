using Test
using Hsm
using ValSplit

@testset "Macros" begin
    @testset "@hsmdef macro" begin
        # Test creating a state machine with @hsmdef
        @hsmdef mutable struct TestSm
            counter::Int
            name::String
        end

        # Test that the struct was created correctly
        sm1 = TestSm(0, "test1")
        @test sm1.counter == 0
        @test sm1.name == "test1"

        # Test keyword constructor
        sm2 = TestSm(counter=42, name="test2")
        @test sm2.counter == 42
        @test sm2.name == "test2"

        # Test keyword constructor ordering doesn't matter
        sm2a = TestSm(name="test2a", counter=43)
        @test sm2a.counter == 43
        @test sm2a.name == "test2a"

        # Test keyword constructor error handling
        @test_throws ArgumentError TestSm(name="missing-counter")
        @test_throws ArgumentError TestSm(counter=10)

        # Test that the struct is mutable
        sm1.counter = 10
        @test sm1.counter == 10

        # Test the Hsm interface methods
        @test Hsm.current(sm1) === :Root
        Hsm.current!(sm1, :State_S)
        @test Hsm.current(sm1) === :State_S

        @test Hsm.source(sm1) === :Root
        Hsm.source!(sm1, :State_S)
        @test Hsm.source(sm1) === :State_S

        # Test the event interface
        @test Hsm.event(sm1) === :None
        Hsm.event!(sm1, :TestEvent)
        @test Hsm.event(sm1) === :TestEvent
    end

    @testset "@ancestor macro" begin
        # Create a state machine for testing ancestor relations
        @hsmdef mutable struct AncestorTestSm
            value::Int
        end

        # Define ancestry
        @ancestor AncestorTestSm begin
            :State_S => :Root
            :State_S1 => :State_S
            :State_S11 => :State_S1
            :State_S2 => :State_S
            :State_S21 => :State_S2
            :State_S211 => :State_S21
        end

        # Create an instance for testing
        sm = AncestorTestSm(0)

        # Test individual ancestry rules
        @test Hsm.ancestor(sm, Val(:State_S)) === :Root
        @test Hsm.ancestor(sm, Val(:State_S1)) === :State_S
        @test Hsm.ancestor(sm, Val(:State_S11)) === :State_S1
        @test Hsm.ancestor(sm, Val(:State_S2)) === :State_S
        @test Hsm.ancestor(sm, Val(:State_S21)) === :State_S2
        @test Hsm.ancestor(sm, Val(:State_S211)) === :State_S21

        # Test single definition syntax
        @ancestor AncestorTestSm :TestState => :Root
        @test Hsm.ancestor(sm, Val(:TestState)) === :Root
    end

    @testset "@on_event, @on_entry, @on_exit, @on_initial macros" begin
        # Create a state machine for testing handlers
        @hsmdef mutable struct HandlerTestSm
            log::Vector{String}
        end

        # Define ancestry
        @ancestor HandlerTestSm begin
            :State_A => :Root
            :State_B => :Root
            :State_A1 => :State_A
        end

        # Define event handlers
        @on_initial function (sm::HandlerTestSm, ::Root)
            push!(sm.log, "Initial handler for Root")
            return Hsm.transition!(sm, :State_A)
        end

        @on_event function (sm::HandlerTestSm, ::State_A, ::Event_X)
            push!(sm.log, "Event_X handled in State_A")
            return Hsm.EventHandled
        end

        @on_event function (sm::HandlerTestSm, ::State_A, ::Event_Y, data)
            push!(sm.log, "Event_Y handled in State_A with data: $data")
            return Hsm.EventHandled
        end

        @on_initial function (sm::HandlerTestSm, ::State_A)
            push!(sm.log, "Initial handler for State_A")
            return Hsm.transition!(sm, :State_A1)
        end

        @on_entry function (sm::HandlerTestSm, ::State_A)
            push!(sm.log, "Entered State_A")
        end

        @on_exit function (sm::HandlerTestSm, ::State_A)
            push!(sm.log, "Exited State_A")
        end

        # Create an instance and initialize it
        sm = HandlerTestSm(String[])
        @test Hsm.current(sm) === :State_A1

        # Test event handler
        Hsm.dispatch!(sm, :Event_X)
        @test sm.log[end] == "Event_X handled in State_A"

        # Test event handler with argument
        Hsm.dispatch!(sm, :Event_Y, "test-data")
        @test sm.log[end] == "Event_Y handled in State_A with data: test-data"

        # Test transition
        Hsm.transition!(sm, :State_B)
        @test Hsm.current(sm) === :State_B

        # Verify exit handler was called during transition
        @test "Exited State_A" in sm.log

        # Reset log and test entry handler
        empty!(sm.log)
        Hsm.transition!(sm, :State_A)
        @test "Entered State_A" in sm.log

        # Test initial handler
        empty!(sm.log)
        # Set current state to A to match our handler definition
        Hsm.current!(sm, :State_A)
        Hsm.source!(sm, :State_A)
        Hsm.on_initial!(sm, :State_A)
        @test "Initial handler for State_A" in sm.log
        @test Hsm.current(sm) === :State_A1
    end

    # Note: Comprehensive default handler tests are in test_default_handlers.jl
end
