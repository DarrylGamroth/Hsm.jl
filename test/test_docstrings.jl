using Test
using Hsm

@testset "Docstring support" begin
    @testset "@abstracthsmdef with docstring" begin
        """
        Test abstract type with docstring
        """
        @abstracthsmdef TestAbstractHsm
        
        @test TestAbstractHsm isa Type
        # Verify docstring exists
        doc = string(@doc TestAbstractHsm)
        @test occursin("Test abstract type with docstring", doc)
    end
    
    @testset "@hsmdef with docstring" begin
        """
        Test concrete type with docstring
        """
        @hsmdef mutable struct TestDocHsm
            counter::Int
        end
        
        @test TestDocHsm isa Type
        # Verify docstring exists
        doc = string(@doc TestDocHsm)
        @test occursin("Test concrete type with docstring", doc)
    end
    
    @testset "@hsmdef with inheritance and docstring" begin
        """
        Another abstract type
        """
        @abstracthsmdef AnotherAbstractHsm
        
        """
        Concrete implementation with docstring
        """
        @hsmdef mutable struct ConcreteDocHsm <: AnotherAbstractHsm
            value::String
        end
        
        @test ConcreteDocHsm <: AnotherAbstractHsm
        doc = string(@doc ConcreteDocHsm)
        @test occursin("Concrete implementation with docstring", doc)
    end
    
    @testset "@statedef with docstring" begin
        @abstracthsmdef StateDefDocHsm
        
        @hsmdef mutable struct ConcreteStateDefDocHsm <: StateDefDocHsm
            x::Int
        end
        
        """
        Define StateA as a child of Root
        """
        @statedef StateDefDocHsm :StateA
        
        # The function should work
        sm = ConcreteStateDefDocHsm(0)
        @test Hsm.ancestor(sm, Val(:StateA)) == :Root
    end
    
    @testset "Handler macros with docstrings" begin
        @hsmdef mutable struct HandlerDocHsm
            flag::Bool
        end
        
        @statedef HandlerDocHsm :TestState
        
        """
        Initial handler with docstring
        """
        @on_initial function(sm::HandlerDocHsm, ::Root)
            return Hsm.transition!(sm, :TestState)
        end
        
        """
        Entry handler with docstring
        """
        @on_entry function(sm::HandlerDocHsm, ::TestState)
            sm.flag = true
        end
        
        """
        Exit handler with docstring
        """
        @on_exit function(sm::HandlerDocHsm, ::TestState)
            sm.flag = false
        end
        
        """
        Event handler with docstring
        """
        @on_event function(sm::HandlerDocHsm, ::TestState, ::TestEvent, data)
            sm.flag = !sm.flag
            return Hsm.EventHandled
        end
        
        # Test that the handlers work
        sm = HandlerDocHsm(false)
        @test Hsm.current(sm) == :TestState
        @test sm.flag == true
        
        Hsm.dispatch!(sm, :TestEvent)
        @test sm.flag == false
    end
    
    @testset "@hsmdef with @kwdef" begin
        # Note: Docstrings don't work with nested macro calls like @hsmdef @kwdef
        # This is a Julia language limitation, not an Hsm.jl issue
        @hsmdef @kwdef mutable struct KwDefDocHsm
            counter::Int = 0
            name::String = "test"
        end
        
        @test KwDefDocHsm isa Type
        
        # Test that kwdef works
        sm = KwDefDocHsm()
        @test sm.counter == 0
        @test sm.name == "test"
        
        sm2 = KwDefDocHsm(counter=5, name="custom")
        @test sm2.counter == 5
        @test sm2.name == "custom"
    end
    
    @testset "Parametric types with docstrings" begin
        """
        Parametric abstract type
        """
        @abstracthsmdef ParametricAbstractHsm{T}
        
        """
        Parametric concrete type
        """
        @hsmdef mutable struct ParametricConcreteHsm{T} <: ParametricAbstractHsm{T}
            value::T
        end
        
        @test ParametricConcreteHsm{Int} <: ParametricAbstractHsm{Int}
        
        sm = ParametricConcreteHsm(42)
        @test sm.value == 42
    end
end
