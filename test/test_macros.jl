using Test
using Hsm
using ValSplit

@testset "Macros" begin
    @testset "@hsmdef macro" begin
        # Test creating a state machine with basic fields
        @hsmdef mutable struct TestSm
            counter::Int
            name::String
        end

        # Test that the struct was created correctly
        sm1 = TestSm(0, "test1")
        @test sm1.counter == 0
        @test sm1.name == "test1"

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
    end

    @testset "@statedef macro" begin
        # Create a state machine for testing ancestor relations
        @hsmdef mutable struct AncestorTestSm
            value::Int
        end

        # Define ancestry
        @statedef AncestorTestSm :State_S
        @statedef AncestorTestSm :State_S1 :State_S
        @statedef AncestorTestSm :State_S11 :State_S1
        @statedef AncestorTestSm :State_S2 :State_S
        @statedef AncestorTestSm :State_S21 :State_S2
        @statedef AncestorTestSm :State_S211 :State_S21

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
        @statedef AncestorTestSm :TestState :Root
        @test Hsm.ancestor(sm, Val(:TestState)) === :Root

        # Test implied parent syntax (should default to :Root)
        @statedef AncestorTestSm :ImpliedRootState
        @test Hsm.ancestor(sm, Val(:ImpliedRootState)) === :Root
    end

    @testset "@on_event, @on_entry, @on_exit, @on_initial macros" begin
        # Create a state machine for testing handlers
        @hsmdef mutable struct HandlerTestSm
            log::Vector{String}
        end

        # Define ancestry
        @statedef HandlerTestSm :State_A
        @statedef HandlerTestSm :State_B
        @statedef HandlerTestSm :State_A1 :State_A

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

    @testset "@hsmdef with abstract type inheritance" begin
        # Define the abstract state machine type and its interface
        @abstracthsmdef AbstractTestSm

        # Create a concrete state machine that inherits from the abstract type
        @hsmdef mutable struct ConcreteTestSm1 <: AbstractTestSm
            value::Int
            name::String
        end

        # Create another concrete state machine from the same abstract type
        @hsmdef mutable struct ConcreteTestSm2 <: AbstractTestSm
            count::Int
        end

        # Test that instances can be created
        sm1 = ConcreteTestSm1(42, "test")
        sm2 = ConcreteTestSm2(99)

        # Test that the concrete types are correct
        @test sm1 isa ConcreteTestSm1
        @test sm2 isa ConcreteTestSm2

        # Test that both are subtypes of the abstract type
        @test sm1 isa AbstractTestSm
        @test sm2 isa AbstractTestSm

        # Test that HSM interface methods work on each concrete type
        # Note: Methods are defined on concrete types, not the abstract type,
        # because each struct has unique gensym'd field names
        @test Hsm.current(sm1) === :Root
        @test Hsm.current(sm2) === :Root

        Hsm.current!(sm1, :State_A)
        Hsm.current!(sm2, :State_B)
        @test Hsm.current(sm1) === :State_A
        @test Hsm.current(sm2) === :State_B

        @test Hsm.source(sm1) === :Root
        @test Hsm.source(sm2) === :Root

        Hsm.source!(sm1, :State_X)
        Hsm.source!(sm2, :State_Y)
        @test Hsm.source(sm1) === :State_X
        @test Hsm.source(sm2) === :State_Y

        # Test that we can use polymorphism with the abstract type for collections
        machines = AbstractTestSm[sm1, sm2]
        @test length(machines) == 2
        @test all(m -> m isa AbstractTestSm, machines)

        # Test that each state machine can access its own current state through the array
        @test Hsm.current(machines[1]) === :State_A
        @test Hsm.current(machines[2]) === :State_B

        # Test ancestor definitions work with concrete types
        @statedef ConcreteTestSm1 :CustomState
        @test Hsm.ancestor(sm1, Val(:CustomState)) === :Root
    end

    @testset "@hsmdef with parametric abstract type inheritance" begin
        # Define the parametric abstract state machine type and its interface
        @abstracthsmdef ParametricTestSm{T}

        # Create concrete state machines with different type parameters
        @hsmdef mutable struct ConcreteParamSm1 <: ParametricTestSm{Int}
            data::Int
        end

        @hsmdef mutable struct ConcreteParamSm2 <: ParametricTestSm{String}
            data::String
        end

        # Create instances
        sm1 = ConcreteParamSm1(123)
        sm2 = ConcreteParamSm2("hello")

        # Test that instances are created correctly
        @test sm1.data == 123
        @test sm2.data == "hello"

        # Test that both work with HSM interface
        @test Hsm.current(sm1) === :Root
        @test Hsm.current(sm2) === :Root

        Hsm.current!(sm1, :State_A)
        Hsm.current!(sm2, :State_B)
        @test Hsm.current(sm1) === :State_A
        @test Hsm.current(sm2) === :State_B

        # Note: Methods are defined on the base ParametricTestSm (not ParametricTestSm{T})
        # This allows polymorphic behavior across all type parameters
    end

    @testset "@hsmdef with multi-parameter abstract type" begin
        # Define the abstract type with multiple parameters and its interface
        @abstracthsmdef MultiParamSm{T,C}

        # Create a concrete state machine
        @hsmdef mutable struct ConcreteMultiSm{T,C} <: MultiParamSm{T,C}
            value::T
            config::C
        end

        # Create instances with different type parameters
        sm1 = ConcreteMultiSm(42, "config")
        sm2 = ConcreteMultiSm(3.14, :symbol)

        # Test HSM interface works
        @test Hsm.current(sm1) === :Root
        @test Hsm.current(sm2) === :Root

        Hsm.current!(sm1, :State_X)
        Hsm.current!(sm2, :State_Y)
        @test Hsm.current(sm1) === :State_X
        @test Hsm.current(sm2) === :State_Y

        # Test field access
        @test sm1.value == 42
        @test sm1.config == "config"
        @test sm2.value ≈ 3.14
        @test sm2.config == :symbol
    end

    # Note: Comprehensive default handler tests are in test_default_handlers.jl
end
