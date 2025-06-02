using Test
using Hsm

@testset "State Machine Behavior" begin
    # Create a more complex state machine for testing state transitions and event propagation
    @hsmdef mutable struct ComplexTestSm
        counter::Int
        log::Vector{String}
    end
    
    # Define state hierarchy
    @ancestor ComplexTestSm begin
        :State_Top => Hsm.Root
        :State_S1 => :State_Top
        :State_S11 => :State_S1
        :State_S12 => :State_S1
        :State_S2 => :State_Top
        :State_S21 => :State_S2
        :State_S211 => :State_S21
    end
    
    # Define handlers for State_Top
    @on_entry :State_Top function(sm::ComplexTestSm)
        push!(sm.log, "Entered State_Top")
    end
    
    @on_exit :State_Top function(sm::ComplexTestSm)
        push!(sm.log, "Exited State_Top")
    end
    
    @on_initial :State_Top function(sm::ComplexTestSm)
        push!(sm.log, "Initial handler for State_Top")
        return Hsm.transition!(sm, :State_S1)
    end
    
    @on_event :State_Top :Event_Reset function(sm::ComplexTestSm)
        push!(sm.log, "Reset event in State_Top")
        sm.counter = 0
        return Hsm.EventHandled
    end
    
    # Define handlers for State_S1
    @on_entry :State_S1 function(sm::ComplexTestSm)
        push!(sm.log, "Entered State_S1")
    end
    
    @on_exit :State_S1 function(sm::ComplexTestSm)
        push!(sm.log, "Exited State_S1")
    end
    
    @on_initial :State_S1 function(sm::ComplexTestSm)
        push!(sm.log, "Initial handler for State_S1")
        return Hsm.transition!(sm, :State_S11)
    end
    
    @on_event :State_S1 :Event_A function(sm::ComplexTestSm)
        push!(sm.log, "Event A in State_S1")
        return Hsm.transition!(sm, :State_S12)
    end
    
    @on_event :State_S1 :Event_B function(sm::ComplexTestSm)
        push!(sm.log, "Event B in State_S1")
        return Hsm.EventNotHandled  # Let it propagate up
    end
    
    # Define handlers for State_S11
    @on_entry :State_S11 function(sm::ComplexTestSm)
        push!(sm.log, "Entered State_S11")
    end
    
    @on_exit :State_S11 function(sm::ComplexTestSm)
        push!(sm.log, "Exited State_S11")
    end
    
    @on_event :State_S11 :Event_C function(sm::ComplexTestSm)
        push!(sm.log, "Event C in State_S11")
        sm.counter += 1
        return Hsm.EventHandled
    end
    
    @on_event :State_S11 :Event_D function(sm::ComplexTestSm)
        push!(sm.log, "Event D in State_S11")
        return Hsm.transition!(sm, :State_S211)
    end
    
    # Define handlers for State_S12
    @on_entry :State_S12 function(sm::ComplexTestSm)
        push!(sm.log, "Entered State_S12")
    end
    
    @on_exit :State_S12 function(sm::ComplexTestSm)
        push!(sm.log, "Exited State_S12")
    end
    
    # Define handlers for State_S2
    @on_entry :State_S2 function(sm::ComplexTestSm)
        push!(sm.log, "Entered State_S2")
    end
    
    @on_exit :State_S2 function(sm::ComplexTestSm)
        push!(sm.log, "Exited State_S2")
    end
    
    @on_initial :State_S2 function(sm::ComplexTestSm)
        push!(sm.log, "Initial handler for State_S2")
        return Hsm.transition!(sm, :State_S21)
    end
    
    @on_event :State_S2 :Event_B function(sm::ComplexTestSm)
        push!(sm.log, "Event B in State_S2")
        sm.counter += 5
        return Hsm.EventHandled
    end
    
    # Define handlers for State_S21
    @on_entry :State_S21 function(sm::ComplexTestSm)
        push!(sm.log, "Entered State_S21")
    end
    
    @on_initial :State_S21 function(sm::ComplexTestSm)
        push!(sm.log, "Initial handler for State_S21")
        return Hsm.transition!(sm, :State_S211)
    end
    
    @on_exit :State_S21 function(sm::ComplexTestSm)
        push!(sm.log, "Exited State_S21")
    end
    
    # Define handlers for State_S211
    @on_entry :State_S211 function(sm::ComplexTestSm)
        push!(sm.log, "Entered State_S211")
    end
    
    @on_exit :State_S211 function(sm::ComplexTestSm)
        push!(sm.log, "Exited State_S211")
    end
    
    @on_event :State_S211 :Event_E function(sm::ComplexTestSm)
        push!(sm.log, "Event E in State_S211")
        return Hsm.transition!(sm, :State_S11)
    end
    
    @testset "Initialization" begin
        # Create a fresh state machine instance
        sm = ComplexTestSm(0, String[])
        
        # Initialize the state machine starting from Top state
        Hsm.on_entry!(sm, :State_Top)  # Call entry handler manually
        Hsm.current!(sm, :State_Top)
        Hsm.source!(sm, :State_Top)
        Hsm.on_initial!(sm, :State_Top)
        
        # Check final state
        @test Hsm.current(sm) === :State_S11
        
        # Check that all expected events happened
        @test "Entered State_Top" in sm.log
        @test "Initial handler for State_Top" in sm.log
        @test "Entered State_S1" in sm.log
        @test "Initial handler for State_S1" in sm.log
        @test "Entered State_S11" in sm.log
    end
    
    @testset "Event Handling and State Transitions" begin
        # Create a fresh state machine instance
        sm = ComplexTestSm(0, String[])
        Hsm.current!(sm, :State_Top)
        Hsm.source!(sm, :State_Top)
        Hsm.on_initial!(sm, :State_Top)
        empty!(sm.log)  # Clear the log
        
        # Test event that causes transition
        Hsm.dispatch!(sm, :Event_A)
        @test Hsm.current(sm) === :State_S12
        @test "Event A in State_S1" in sm.log
        @test "Exited State_S11" in sm.log
        @test "Entered State_S12" in sm.log
        
        # Test event that propagates up the hierarchy
        empty!(sm.log)
        Hsm.dispatch!(sm, :Event_B)
        @test "Event B in State_S1" in sm.log
        # Should not be handled since S12 doesn't handle B and S1 returns EventNotHandled
        @test sm.counter == 0
        
        # Test complex transition to another branch of the state hierarchy
        empty!(sm.log)
        Hsm.transition!(sm, :State_S211)
        @test Hsm.current(sm) === :State_S211
        @test "Exited State_S12" in sm.log
        @test "Exited State_S1" in sm.log
        @test "Entered State_S2" in sm.log
        @test "Entered State_S21" in sm.log
        @test "Entered State_S211" in sm.log
        
        # Test event handled only in one specific state
        empty!(sm.log)
        Hsm.dispatch!(sm, :Event_E)
        @test Hsm.current(sm) === :State_S11
        @test "Event E in State_S211" in sm.log
        @test "Exited State_S211" in sm.log
        @test "Exited State_S21" in sm.log
        @test "Exited State_S2" in sm.log
        @test "Entered State_S1" in sm.log
        @test "Entered State_S11" in sm.log
        
        # Test event with counter update
        empty!(sm.log)
        Hsm.dispatch!(sm, :Event_C)
        @test sm.counter == 1
        @test "Event C in State_S11" in sm.log
        
        # Test event handled at higher level in hierarchy
        empty!(sm.log)
        Hsm.dispatch!(sm, :Event_Reset)
        @test sm.counter == 0
        @test "Reset event in State_Top" in sm.log
    end
    
    @testset "Direct State Transitions" begin
        # Create a fresh state machine instance
        sm = ComplexTestSm(0, String[])
        Hsm.current!(sm, :State_Top)
        Hsm.source!(sm, :State_Top)
        Hsm.on_initial!(sm, :State_Top)
        empty!(sm.log)
        
        # Test transition that triggers exit handlers from current branch
        # and initial handlers in the new branch
        Hsm.transition!(sm, :State_S2)
        @test Hsm.current(sm) === :State_S211
        
        # Exit handlers for previous state path should be called
        @test "Exited State_S11" in sm.log
        @test "Exited State_S1" in sm.log
        
        # Entry handlers for new state path should be called
        @test "Entered State_S2" in sm.log
        @test "Initial handler for State_S2" in sm.log
        @test "Entered State_S21" in sm.log
        @test "Initial handler for State_S21" in sm.log
        @test "Entered State_S211" in sm.log
    end
end
