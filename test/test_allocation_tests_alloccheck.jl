using Test
using Hsm
using AllocCheck

# AllocCheck 0.2.6 reports the exception frame required by dispatch!'s
# try/finally as a potential allocation on Windows. Runtime allocation tests
# still run there; static allocation checks apply on the other CI platforms.
alloccheck_dispatch!(sm, event, arg=nothing) = Hsm.dispatch!(sm, event, arg)

@testset "AllocCheck steady-state contract" begin
    @hsmdef mutable struct AllocationContractSm
        counter::Int
    end

    @statedef AllocationContractSm :AllocationParent
    @statedef AllocationContractSm :AllocationLeaf :AllocationParent
    @statedef AllocationContractSm :AllocationOther

    @on_initial function (sm::AllocationContractSm, ::Root)
        return Hsm.transition!(sm, :AllocationParent)
    end

    @on_initial function (sm::AllocationContractSm, ::AllocationParent)
        return Hsm.transition!(sm, :AllocationLeaf)
    end

    @on_event function (
        sm::AllocationContractSm,
        ::AllocationLeaf,
        ::AllocationHandled,
        arg::Int,
    )
        sm.counter += arg
        return Hsm.EventHandled
    end

    @on_event function (
        sm::AllocationContractSm,
        ::AllocationParent,
        ::AllocationAncestor,
        arg::Vector{Int},
    )
        sm.counter += length(arg)
        return Hsm.EventHandled
    end

    @on_event function (
        sm::AllocationContractSm,
        ::AllocationLeaf,
        ::AllocationMove,
        arg,
    )
        return Hsm.transition!(sm, :AllocationOther) do
            sm.counter += 10
        end
    end

    @on_event function (
        sm::AllocationContractSm,
        ::AllocationOther,
        ::AllocationSelf,
        arg,
    )
        return Hsm.transition!(sm, :AllocationOther) do
            sm.counter += 100
        end
    end

    @on_event function (
        sm::AllocationContractSm,
        ::AllocationOther,
        ::AllocationReturn,
        arg,
    )
        return Hsm.transition!(sm, :AllocationParent)
    end

    @on_event function (
        sm::AllocationContractSm,
        state::Any,
        event::Any,
        arg,
    )
        return Hsm.EventNotHandled
    end

    @testset "dispatch and transition paths" begin
        sm = AllocationContractSm(0)
        @test Hsm.current(sm) === :AllocationLeaf

        @test alloccheck_dispatch!(sm, :AllocationHandled, 2) ===
              Hsm.EventHandled
        @test sm.counter == 2

        payload = [1, 2, 3]
        @test alloccheck_dispatch!(sm, :AllocationAncestor, payload) ===
              Hsm.EventHandled
        @test sm.counter == 5

        @test alloccheck_dispatch!(sm, :AllocationUnknown) ===
              Hsm.EventNotHandled
        @test Hsm.current(sm) === :AllocationLeaf

        @test alloccheck_dispatch!(sm, :AllocationMove) === Hsm.EventHandled
        @test Hsm.current(sm) === :AllocationOther
        @test sm.counter == 15

        @test alloccheck_dispatch!(sm, :AllocationSelf) === Hsm.EventHandled
        @test Hsm.current(sm) === :AllocationOther
        @test sm.counter == 115

        @test alloccheck_dispatch!(sm, :AllocationReturn) === Hsm.EventHandled
        @test Hsm.current(sm) === :AllocationLeaf

        @test Hsm.transition!(sm, :AllocationOther) === Hsm.EventHandled
        @test Hsm.current(sm) === :AllocationOther
        @test Hsm.transition!(sm, :AllocationParent) === Hsm.EventHandled
        @test Hsm.current(sm) === :AllocationLeaf
    end

    @abstracthsmdef AbstractAllocationContractSm

    @hsmdef mutable struct AbstractAllocationA <: AbstractAllocationContractSm
        counter::Int
    end

    @hsmdef mutable struct AbstractAllocationB <: AbstractAllocationContractSm
        counter::Int
    end

    @statedef AbstractAllocationContractSm :AbstractAllocationIdle
    @statedef AbstractAllocationContractSm :AbstractAllocationMoving

    @on_initial function (sm::AbstractAllocationContractSm, ::Root)
        return Hsm.transition!(sm, :AbstractAllocationIdle)
    end

    @on_event function (
        sm::AbstractAllocationContractSm,
        ::AbstractAllocationIdle,
        ::AbstractAllocationStart,
        arg::Int,
    )
        sm.counter += arg
        return Hsm.transition!(sm, :AbstractAllocationMoving)
    end

    @on_event function (
        sm::AbstractAllocationContractSm,
        ::AbstractAllocationMoving,
        ::AbstractAllocationReset,
        arg,
    )
        return Hsm.transition!(sm, :AbstractAllocationIdle)
    end

    @on_event function (
        sm::AbstractAllocationA,
        ::AbstractAllocationMoving,
        ::AbstractAllocationSpecific,
        arg::Int,
    )
        sm.counter += arg
        return Hsm.EventHandled
    end

    @testset "abstract shared and concrete handlers" begin
        first = AbstractAllocationA(0)
        second = AbstractAllocationB(0)

        for sm in (first, second)
            @test alloccheck_dispatch!(sm, :AbstractAllocationStart, 1) ===
                  Hsm.EventHandled
            @test Hsm.current(sm) === :AbstractAllocationMoving
            @test sm.counter == 1
        end

        @test alloccheck_dispatch!(first, :AbstractAllocationSpecific, 2) ===
              Hsm.EventHandled
        @test first.counter == 3

        for sm in (first, second)
            @test alloccheck_dispatch!(sm, :AbstractAllocationReset) ===
                  Hsm.EventHandled
            @test Hsm.current(sm) === :AbstractAllocationIdle
        end
    end

    # AllocCheck conservatively reports generated recursive calls for nested
    # state paths as DynamicDispatch on supported Julia versions. Reject every
    # concrete allocation or allocating runtime-call site without treating that
    # compiler-dependent dispatch report as an allocation defect.
    @static if !Sys.iswindows()
        for signature in (
            (AllocationContractSm, Symbol, Int),
            (AllocationContractSm, Symbol, Vector{Int}),
            (AllocationContractSm, Symbol, Nothing),
            (AbstractAllocationA, Symbol, Int),
            (AbstractAllocationB, Symbol, Nothing),
        )
            sites = AllocCheck.check_allocs(Hsm.dispatch!, signature)
            @test all(site -> site isa AllocCheck.DynamicDispatch, sites)
        end
    end
end
