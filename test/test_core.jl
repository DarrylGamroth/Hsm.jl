using Test
using Hsm

@testset "Core functionality" begin
    # Test that the Root constant is defined
    @test Hsm.Root === :Root

    # Test the EventHandled and EventNotHandled enum values
    @test Hsm.EventHandled isa Hsm.EventReturn
    @test Hsm.EventNotHandled isa Hsm.EventReturn
    @test Hsm.EventHandled != Hsm.EventNotHandled

    # Test manually creating a simple state machine
    mutable struct TestManualSm
        _current::Symbol
        _source::Symbol
        counter::Int
        # Add a state hierarchy map for the ancestor interface
        _ancestors::Dict{Symbol, Symbol}
        
        function TestManualSm(current::Symbol, source::Symbol, counter::Int)
            # Initialize with a simple state hierarchy
            ancestors = Dict{Symbol, Symbol}(
                :State_S => :Root,
                :State_S1 => :State_S,
                :State_S2 => :State_S,
                :State_S11 => :State_S1,
                :State_S21 => :State_S2
            )
            new(current, source, counter, ancestors)
        end
    end
    
    # Implement the Hsm interface
    Hsm.current(sm::TestManualSm) = sm._current
    Hsm.current!(sm::TestManualSm, state::Symbol) = (sm._current = state)
    Hsm.source(sm::TestManualSm) = sm._source
    Hsm.source!(sm::TestManualSm, state::Symbol) = (sm._source = state)
    
    # Implement the ancestor interface
    Hsm.ancestor(sm::TestManualSm, state::Symbol) = get(sm._ancestors, state, :Root)

    # Create an instance
    sm = TestManualSm(:Root, :Root, 0)
    
    # Test current/source getters and setters
    @test Hsm.current(sm) === :Root
    @test Hsm.source(sm) === :Root
    
    Hsm.current!(sm, :State_S1)
    Hsm.source!(sm, :State_S)
    
    @test Hsm.current(sm) === :State_S1
    @test Hsm.source(sm) === :State_S
    
    # Test ancestor interface
    @test Hsm.ancestor(sm, :State_S1) === :State_S
    @test Hsm.ancestor(sm, :State_S11) === :State_S1
    @test Hsm.ancestor(sm, :State_S) === :Root
    @test Hsm.ancestor(sm, :Root) === :Root
    @test Hsm.ancestor(sm, :NonExistentState) === :Root  # Default to Root for unknown states
    
    # Test the Hsm.isancestorof function which is provided by the library
    @test Hsm.isancestorof(sm, :State_S, :State_S1) === true
    @test Hsm.isancestorof(sm, :State_S, :State_S11) === true
    @test Hsm.isancestorof(sm, :State_S1, :State_S11) === true
    @test Hsm.isancestorof(sm, :Root, :State_S) === true   # Root is an ancestor of all states
    @test Hsm.isancestorof(sm, :Root, :Root) === true      # Root is an ancestor of itself
    @test Hsm.isancestorof(sm, :State_S1, :State_S2) === false
    @test Hsm.isancestorof(sm, :State_S11, :State_S1) === false  # Child is not ancestor of parent
    @test Hsm.isancestorof(sm, :State_S, :State_S) === false  # A state is not its own ancestor (except Root)
    
    # Basic tests for find_lca within the main testset
    @test Hsm.find_lca(sm, :State_S11, :State_S21) === :State_S  # LCA of two leaf states
    @test Hsm.find_lca(sm, :State_S1, :State_S2) === :State_S    # LCA of two direct children
end

@testset "Lowest Common Ancestor (LCA)" begin
    # Create a state machine with a more complex hierarchy for LCA testing
    mutable struct TestLcaSm
        _current::Symbol
        _source::Symbol
        _ancestors::Dict{Symbol, Symbol}
        
        function TestLcaSm()
            # Initialize with a more complex state hierarchy for LCA testing
            #            Root
            #           /    \
            #       StateA    StateB
            #      /     \      /   \
            #  StateA1  StateA2 StateB1 StateB2
            #    |         |      |
            # StateA11   StateA21 StateB11
            #                      |
            #                    StateB111
            ancestors = Dict{Symbol, Symbol}(
                :StateA => :Root,
                :StateB => :Root,
                :StateA1 => :StateA,
                :StateA2 => :StateA,
                :StateB1 => :StateB,
                :StateB2 => :StateB,
                :StateA11 => :StateA1,
                :StateA21 => :StateA2,
                :StateB11 => :StateB1,
                :StateB111 => :StateB11
            )
            new(:Root, :Root, ancestors)
        end
    end
    
    # Implement the minimal ancestor interface for LCA testing
    Hsm.ancestor(sm::TestLcaSm, state::Symbol) = get(sm._ancestors, state, :Root)
    
    # Create an instance
    lca_sm = TestLcaSm()
    
    # Test various LCA scenarios
    # Same level, different branches
    @test Hsm.find_lca(lca_sm, :StateA1, :StateA2) === :StateA
    @test Hsm.find_lca(lca_sm, :StateB1, :StateB2) === :StateB
    @test Hsm.find_lca(lca_sm, :StateA11, :StateA21) === :StateA
    
    # Different depths, same branch
    @test Hsm.find_lca(lca_sm, :StateA11, :StateA1) === :StateA1  # Child and parent - LCA is parent
    @test Hsm.find_lca(lca_sm, :StateB111, :StateB1) === :StateB1  # Grandchild and grandparent
    @test Hsm.find_lca(lca_sm, :StateB111, :StateB11) === :StateB11  # Direct child-parent
    
    # Different depths, different branches
    @test Hsm.find_lca(lca_sm, :StateA11, :StateB111) === :Root  # Completely different branches
    @test Hsm.find_lca(lca_sm, :StateA, :StateB111) === :Root  # Branch root and deep leaf
    
    # Identical states
    @test Hsm.find_lca(lca_sm, :StateA, :StateA) === :Root  # LCA with self is parent
    @test Hsm.find_lca(lca_sm, :Root, :Root) === :Root  # Root's LCA is Root
    
    # With Root
    @test Hsm.find_lca(lca_sm, :StateA1, :Root) === :Root  # Any state with Root gives Root
    
    # With non-existent state
    @test Hsm.find_lca(lca_sm, :StateA11, :NonExistentState) === :Root  # Unknown state defaults to Root
    @test Hsm.find_lca(lca_sm, :NonExistentState1, :NonExistentState2) === :Root  # Both unknown
end
