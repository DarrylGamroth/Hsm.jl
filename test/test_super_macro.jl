using Test
using Hsm

@testset "Super Macro Tests" begin
    @testset "on_event handler" begin
        @abstracthsmdef AbstractVehicle

        @hsmdef mutable struct Car <: AbstractVehicle
            engine_running::Bool
            wheels::Int
            abstract_called::Bool
            concrete_called::Bool
        end

        @statedef AbstractVehicle :Stopped
        @statedef AbstractVehicle :Running :Stopped

        # Initial state transition
        @on_initial function(sm::AbstractVehicle, ::Root)
            return Hsm.transition!(sm, :Stopped)
        end

        # Abstract handler
        @on_event function(sm::AbstractVehicle, state::Stopped, event::StartEngine, data)
            sm.engine_running = true
            sm.abstract_called = true
            return Hsm.EventHandled
        end

        # Concrete handler that calls abstract
        @on_event function(sm::Car, state::Stopped, event::StartEngine, data)
            result = @super on_event sm state event data
            sm.concrete_called = true
            sm.wheels = data
            return result
        end

        car = Car(false, 0, false, false)
        result = Hsm.dispatch!(car, :StartEngine, 4)

        @test result == Hsm.EventHandled
        @test car.engine_running == true  # Set by abstract handler
        @test car.abstract_called == true
        @test car.concrete_called == true
        @test car.wheels == 4  # Set by concrete handler
    end

    @testset "on_initial handler" begin
        @abstracthsmdef AbstractDevice

        @hsmdef mutable struct Phone <: AbstractDevice
            initialized::Bool
            device_ready::Bool
            phone_ready::Bool
        end

        @statedef AbstractDevice :Ready

        # Abstract handler
        @on_initial function(sm::AbstractDevice, state::Root)
            sm.device_ready = true
            return Hsm.transition!(sm, :Ready)
        end

        # Concrete handler that calls abstract
        @on_initial function(sm::Phone, state::Root)
            result = @super on_initial sm state
            sm.phone_ready = true
            return result  # Propagate the transition
        end

        phone = Phone(false, false, false)

        @test phone.device_ready == true  # Set by abstract handler during construction
        @test phone.phone_ready == true   # Set by concrete handler during construction
        @test Hsm.current(phone) == :Ready
    end

    @testset "on_entry handler" begin
        @abstracthsmdef AbstractMachine

        @hsmdef mutable struct ConcreteMachine <: AbstractMachine
            abstract_entered::Bool
            concrete_entered::Bool
            entry_order::Vector{Symbol}
        end

        @statedef AbstractMachine :Active

        # Abstract handler
        @on_entry function(sm::AbstractMachine, state::Active)
            sm.abstract_entered = true
            push!(sm.entry_order, :abstract)
        end

        # Concrete handler that calls abstract
        @on_entry function(sm::ConcreteMachine, state::Active)
            @super on_entry sm state
            sm.concrete_entered = true
            push!(sm.entry_order, :concrete)
        end

        machine = ConcreteMachine(false, false, Symbol[])
        Hsm.on_entry!(machine, Val(:Active))

        @test machine.abstract_entered == true
        @test machine.concrete_entered == true
        @test machine.entry_order == [:abstract, :concrete]
    end

    @testset "on_exit handler" begin
        @abstracthsmdef AbstractSystem

        @hsmdef mutable struct ConcreteSystem <: AbstractSystem
            abstract_exited::Bool
            concrete_exited::Bool
            exit_order::Vector{Symbol}
        end

        @statedef AbstractSystem :Running

        # Abstract handler
        @on_exit function(sm::AbstractSystem, state::Running)
            sm.abstract_exited = true
            push!(sm.exit_order, :abstract)
        end

        # Concrete handler that calls abstract
        @on_exit function(sm::ConcreteSystem, state::Running)
            @super on_exit sm state
            sm.concrete_exited = true
            push!(sm.exit_order, :concrete)
        end

        system = ConcreteSystem(false, false, Symbol[])
        Hsm.on_exit!(system, Val(:Running))

        @test system.abstract_exited == true
        @test system.concrete_exited == true
        @test system.exit_order == [:abstract, :concrete]
    end

    @testset "Return value propagation" begin
        @abstracthsmdef AbstractController

        @hsmdef mutable struct Controller <: AbstractController
            value::Int
        end

        @statedef AbstractController :Idle

        # Initial state transition
        @on_initial function(sm::AbstractController, ::Root)
            return Hsm.transition!(sm, :Idle)
        end

        # Abstract handler that returns EventNotHandled
        @on_event function(sm::AbstractController, state::Idle, event::Ping, data)
            sm.value = data
            return Hsm.EventNotHandled
        end

        # Concrete handler that propagates the return value
        @on_event function(sm::Controller, state::Idle, event::Ping, data)
            result = @super on_event sm state event data
            @test result == Hsm.EventNotHandled
            return result
        end

        controller = Controller(0)
        result = Hsm.dispatch!(controller, :Ping, 42)

        @test result == Hsm.EventNotHandled
        @test controller.value == 42
    end

    @testset "Error handling - no abstract handler" begin
        @abstracthsmdef AbstractWidget

        @hsmdef mutable struct Widget <: AbstractWidget
            data::Int
        end

        @statedef AbstractWidget :Active

        # Initial state transition
        @on_initial function(sm::AbstractWidget, ::Root)
            return Hsm.transition!(sm, :Active)
        end

        # No abstract handler defined for this event

        # Concrete handler tries to call non-existent abstract handler
        @on_event function(sm::Widget, state::Active, event::MissingEvent, data)
            @super on_event sm state event data  # Should throw MethodError
        end

        widget = Widget(0)
        
        @test_throws MethodError Hsm.dispatch!(widget, :MissingEvent, 1)
    end

    @testset "Multiple inheritance levels" begin
        @abstracthsmdef AbstractBase

        @hsmdef mutable struct Derived1 <: AbstractBase
            base_called::Bool
            derived1_called::Bool
        end

        @statedef AbstractBase :State1

        # Initial state transition
        @on_initial function(sm::AbstractBase, ::Root)
            return Hsm.transition!(sm, :State1)
        end

        # Base handler
        @on_event function(sm::AbstractBase, state::State1, event::Event1, data)
            sm.base_called = true
            return Hsm.EventHandled
        end

        # Derived handler calls base
        @on_event function(sm::Derived1, state::State1, event::Event1, data)
            @super on_event sm state event data
            sm.derived1_called = true
            return Hsm.EventHandled
        end

        derived = Derived1(false, false)
        Hsm.dispatch!(derived, :Event1, nothing)

        @test derived.base_called == true
        @test derived.derived1_called == true
    end

    @testset "Named state and event parameters" begin
        @abstracthsmdef AbstractApp

        @hsmdef mutable struct App <: AbstractApp
            state_value::Symbol
            event_value::Symbol
        end

        @statedef AbstractApp :Running

        # Initial state transition
        @on_initial function(sm::AbstractApp, ::Root)
            return Hsm.transition!(sm, :Running)
        end

        # Abstract handler with named parameters
        @on_event function(sm::AbstractApp, state::Running, event::Update, data)
            sm.state_value = state
            sm.event_value = event
            return Hsm.EventHandled
        end

        # Concrete handler using named parameters
        @on_event function(sm::App, state::Running, event::Update, data)
            @super on_event sm state event data
            @test state == :Running
            @test event == :Update
            return Hsm.EventHandled
        end

        app = App(:None, :None)
        Hsm.dispatch!(app, :Update, nothing)

        @test app.state_value == :Running
        @test app.event_value == :Update
    end
end
