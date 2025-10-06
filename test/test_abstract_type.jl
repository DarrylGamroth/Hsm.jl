using Test
using Hsm

@testset "Abstract Type Support" begin  
    # Create the abstract interface once
    @abstracthsmdef AbstractTestStateMachine
    
    # Create two concrete state machines that inherit from the abstract type
    @hsmdef mutable struct ConcreteStateMachine1 <: AbstractTestStateMachine
        counter::Int
    end
    
    @hsmdef mutable struct ConcreteStateMachine2 <: AbstractTestStateMachine
        value::String
    end
    
    # Define state hierarchy on the abstract type (shared across both concrete types)
    @statedef AbstractTestStateMachine :StateA
    @statedef AbstractTestStateMachine :StateB
    @statedef AbstractTestStateMachine :StateC :StateA
    
    # Define default handlers on the abstract type
    @on_entry function(sm::AbstractTestStateMachine, ::StateA)
        # This will work for both ConcreteStateMachine1 and ConcreteStateMachine2
        if sm isa ConcreteStateMachine1
            sm.counter += 1
        elseif sm isa ConcreteStateMachine2
            sm.value = sm.value * "A"
        end
    end
    
    @on_event function(sm::AbstractTestStateMachine, ::StateA, ::EventX)
        return Hsm.transition!(sm, :StateC)
    end
    
    @testset "Concrete type field accessors work independently" begin
        sm1 = ConcreteStateMachine1(0)
        sm2 = ConcreteStateMachine2("test")
        
        # Both should start in Root state
        @test Hsm.current(sm1) == :Root
        @test Hsm.current(sm2) == :Root
        
        # Field accessors work on concrete types
        Hsm.current!(sm1, :StateA)
        Hsm.current!(sm2, :StateB)
        
        @test Hsm.current(sm1) == :StateA
        @test Hsm.current(sm2) == :StateB
        
        # Verify they have independent state
        @test sm1.counter == 0
        @test sm2.value == "test"
    end
    
    @testset "Ancestor relationships defined on abstract type work for both" begin
        sm1 = ConcreteStateMachine1(0)
        sm2 = ConcreteStateMachine2("")
        
        # Both should have the same state hierarchy
        @test Hsm.ancestor(sm1, Val(:StateA)) == :Root
        @test Hsm.ancestor(sm2, Val(:StateA)) == :Root
        @test Hsm.ancestor(sm1, Val(:StateC)) == :StateA
        @test Hsm.ancestor(sm2, Val(:StateC)) == :StateA
    end
    
    @testset "Shared handlers on abstract type work for both concrete types" begin
        sm1 = ConcreteStateMachine1(5)
        sm2 = ConcreteStateMachine2("value")
        
        # Transition both to StateA (triggers on_entry)
        Hsm.transition!(sm1, :StateA)
        Hsm.transition!(sm2, :StateA)
        
        # Verify the shared on_entry handler worked correctly for each type
        @test sm1.counter == 6  # incremented
        @test sm2.value == "valueA"  # appended "A"
        
        # Both should be in StateA
        @test Hsm.current(sm1) == :StateA
        @test Hsm.current(sm2) == :StateA
    end
    
    @testset "Shared event handlers work for both types" begin
        sm1 = ConcreteStateMachine1(0)
        sm2 = ConcreteStateMachine2("")
        
        Hsm.transition!(sm1, :StateA)
        Hsm.transition!(sm2, :StateA)
        
        # Dispatch the same event to both
        result1 = Hsm.dispatch!(sm1, :EventX)
        result2 = Hsm.dispatch!(sm2, :EventX)
        
        # Both should have transitioned to StateC
        @test Hsm.current(sm1) == :StateC
        @test Hsm.current(sm2) == :StateC
    end
    
    @testset "Polymorphic collections work" begin
        sm1 = ConcreteStateMachine1(10)
        sm2 = ConcreteStateMachine2("hello")
        
        # Create a vector with abstract type
        machines = AbstractTestStateMachine[sm1, sm2]
        
        @test length(machines) == 2
        @test machines[1] isa ConcreteStateMachine1
        @test machines[2] isa ConcreteStateMachine2
        
        # Can call methods through abstract type
        for sm in machines
            Hsm.transition!(sm, :StateB)
        end
        
        @test Hsm.current(sm1) == :StateB
        @test Hsm.current(sm2) == :StateB
    end
    
    @testset "Concrete-specific handlers can override abstract handlers" begin
        # Define a specific handler for ConcreteStateMachine1 only for StateB
        @on_entry function(sm::ConcreteStateMachine1, ::StateB)
            sm.counter = 999
        end
        
        # Define a handler on abstract type for StateB  
        @on_entry function(sm::AbstractTestStateMachine, ::StateB)
            if sm isa ConcreteStateMachine2
                sm.value = sm.value * "B"
            end
        end
        
        sm1 = ConcreteStateMachine1(0)
        sm2 = ConcreteStateMachine2("test")
        
        Hsm.transition!(sm1, :StateB)
        Hsm.transition!(sm2, :StateB)
        
        # sm1 should use the concrete-specific handler (more specific dispatch)
        @test sm1.counter == 999
        
        # sm2 should use the abstract handler
        @test sm2.value == "testB"
    end
end
