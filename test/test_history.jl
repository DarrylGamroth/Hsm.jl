using Test
using Hsm
using AllocCheck

@testset "History transitions" begin
    @hsmdef mutable struct HistoryTestSm
        log::Vector{Symbol}
        branch_initials::Int
    end

    @statedef HistoryTestSm :Composite
    @statedef HistoryTestSm :Branch :Composite
    @statedef HistoryTestSm :Leaf1 :Branch
    @statedef HistoryTestSm :Leaf2 :Branch
    @statedef HistoryTestSm :Outside

    @on_initial function (sm::HistoryTestSm, ::Root)
        return Hsm.transition!(sm, :Composite)
    end

    @on_initial function (sm::HistoryTestSm, ::Composite)
        return Hsm.transition!(sm, :Branch)
    end

    @on_initial function (sm::HistoryTestSm, ::Branch)
        sm.branch_initials += 1
        return Hsm.transition!(sm, :Leaf1)
    end

    @on_entry function (sm::HistoryTestSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::HistoryTestSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_event function (sm::HistoryTestSm, ::Leaf1, ::Next, arg)
        return Hsm.transition!(sm, :Leaf2)
    end

    @on_event function (sm::HistoryTestSm, ::Leaf2, ::Leave, arg)
        return Hsm.transition!(sm, :Outside)
    end

    @on_event function (sm::HistoryTestSm, ::Outside, ::RecallShallow, arg)
        return Hsm.transition_history!(sm, :Composite, Hsm.ShallowHistory()) do
            push!(sm.log, :history_action)
        end
    end

    @on_event function (sm::HistoryTestSm, ::Outside, ::RecallDeep, arg)
        return Hsm.transition_history!(sm, :Composite, Hsm.DeepHistory())
    end

    shallow = HistoryTestSm(Symbol[], 0)
    @test Hsm.current(shallow) === :Leaf1
    @test shallow.branch_initials == 1
    @test Hsm._history_storage(shallow) isa Vector{Symbol}
    @test length(Hsm._history_storage(shallow)) == 1
    Hsm.dispatch!(shallow, :Next)
    Hsm.dispatch!(shallow, :Leave)
    empty!(shallow.log)

    @test Hsm.dispatch!(shallow, :RecallShallow) === Hsm.EventHandled
    @test Hsm.current(shallow) === :Leaf1
    @test shallow.branch_initials == 2
    @test shallow.log == [
        :exit_Outside,
        :history_action,
        :enter_Composite,
        :enter_Branch,
        :enter_Leaf1,
    ]

    deep = HistoryTestSm(Symbol[], 0)
    Hsm.dispatch!(deep, :Next)
    Hsm.dispatch!(deep, :Leave)
    empty!(deep.log)
    initial_count = deep.branch_initials

    @test Hsm.dispatch!(deep, :RecallDeep) === Hsm.EventHandled
    @test Hsm.current(deep) === :Leaf2
    @test deep.branch_initials == initial_count
    @test deep.log == [
        :exit_Outside,
        :enter_Composite,
        :enter_Branch,
        :enter_Leaf2,
    ]

    # The public Symbol API retains a dynamic boundary outside handler macros.
    Hsm.dispatch!(deep, :Leave)
    @test Hsm.transition_history!(deep, :Composite, Hsm.DeepHistory()) ===
          Hsm.EventHandled
    @test Hsm.current(deep) === :Leaf2

    @test_throws Hsm.HsmStateError Hsm.transition_history!(
        deep,
        :Leaf1,
        Hsm.DeepHistory(),
    )
    @test_throws Hsm.HsmStateError Hsm.transition_history!(
        deep,
        :Missing,
        Hsm.DeepHistory(),
    )

    @hsmdef mutable struct DefaultHistoryTestSm end

    @statedef DefaultHistoryTestSm :DefaultComposite
    @statedef DefaultHistoryTestSm :DefaultLeaf :DefaultComposite
    @statedef DefaultHistoryTestSm :DefaultOutside

    @on_initial function (sm::DefaultHistoryTestSm, ::Root)
        return Hsm.transition!(sm, :DefaultOutside)
    end

    @on_initial function (sm::DefaultHistoryTestSm, ::DefaultComposite)
        return Hsm.transition!(sm, :DefaultLeaf)
    end

    @on_event function (sm::DefaultHistoryTestSm, ::DefaultOutside, ::Recall, arg)
        return Hsm.transition_history!(
            sm,
            :DefaultComposite,
            Hsm.DeepHistory(),
        )
    end

    no_history = DefaultHistoryTestSm()
    @test Hsm.current(no_history) === :DefaultOutside
    @test Hsm.dispatch!(no_history, :Recall) === Hsm.EventHandled
    @test Hsm.current(no_history) === :DefaultLeaf

    @hsmdef mutable struct ExplicitDefaultHistorySm
        log::Vector{Symbol}
    end

    @statedef ExplicitDefaultHistorySm :ExplicitComposite
    @statedef ExplicitDefaultHistorySm :InitialLeaf :ExplicitComposite
    @statedef ExplicitDefaultHistorySm :DefaultBranch :ExplicitComposite
    @statedef ExplicitDefaultHistorySm :DefaultBranchLeaf :DefaultBranch
    @statedef ExplicitDefaultHistorySm :DeepDefault :DefaultBranch
    @statedef ExplicitDefaultHistorySm :ExplicitOutside
    @historydef ExplicitDefaultHistorySm :ExplicitComposite Hsm.DeepHistory() :DeepDefault
    @historydef ExplicitDefaultHistorySm :ExplicitComposite Hsm.ShallowHistory() :DefaultBranch

    @on_initial function (sm::ExplicitDefaultHistorySm, ::Root)
        return Hsm.transition!(sm, :ExplicitOutside)
    end

    @on_initial function (sm::ExplicitDefaultHistorySm, ::ExplicitComposite)
        return Hsm.transition!(sm, :InitialLeaf)
    end

    @on_initial function (sm::ExplicitDefaultHistorySm, ::DefaultBranch)
        return Hsm.transition!(sm, :DefaultBranchLeaf)
    end

    @on_entry function (sm::ExplicitDefaultHistorySm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::ExplicitDefaultHistorySm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_history_default function (
        sm::ExplicitDefaultHistorySm,
        ::ExplicitComposite,
        ::DeepHistory,
    )
        push!(sm.log, :deep_default_effect)
        return nothing
    end

    @on_history_default function (
        sm::ExplicitDefaultHistorySm,
        ::ExplicitComposite,
        ::ShallowHistory,
    )
        push!(sm.log, :shallow_default_effect)
        return nothing
    end

    @on_event function (
        sm::ExplicitDefaultHistorySm,
        ::ExplicitOutside,
        ::RecallDeepDefault,
        arg,
    )
        return Hsm.transition_history!(
            sm,
            :ExplicitComposite,
            Hsm.DeepHistory(),
        ) do
            push!(sm.log, :incoming_effect)
        end
    end

    @on_event function (
        sm::ExplicitDefaultHistorySm,
        ::ExplicitOutside,
        ::RecallShallowDefault,
        arg,
    )
        return Hsm.transition_history!(
            sm,
            :ExplicitComposite,
            Hsm.ShallowHistory(),
        )
    end

    explicit_deep = ExplicitDefaultHistorySm(Symbol[])
    empty!(explicit_deep.log)
    @test length(Hsm._history_storage(explicit_deep)) == 1
    @test Hsm.dispatch!(explicit_deep, :RecallDeepDefault) === Hsm.EventHandled
    @test Hsm.current(explicit_deep) === :DeepDefault
    @test explicit_deep.log == [
        :exit_ExplicitOutside,
        :incoming_effect,
        :deep_default_effect,
        :enter_ExplicitComposite,
        :enter_DefaultBranch,
        :enter_DeepDefault,
    ]

    explicit_shallow = ExplicitDefaultHistorySm(Symbol[])
    empty!(explicit_shallow.log)
    @test Hsm.transition_history!(
        explicit_shallow,
        :ExplicitComposite,
        Hsm.ShallowHistory(),
    ) === Hsm.EventHandled
    @test Hsm.current(explicit_shallow) === :DefaultBranchLeaf
    @test explicit_shallow.log == [
        :exit_ExplicitOutside,
        :shallow_default_effect,
        :enter_ExplicitComposite,
        :enter_DefaultBranch,
        :enter_DefaultBranchLeaf,
    ]

    @hsmdef mutable struct InvalidDefaultHistorySm end
    @statedef InvalidDefaultHistorySm :InvalidOwner
    @statedef InvalidDefaultHistorySm :InvalidChild :InvalidOwner
    @historydef InvalidDefaultHistorySm :InvalidOwner Hsm.DeepHistory() :MissingDefault
    @test_throws Hsm.HsmStateError InvalidDefaultHistorySm()

    @hsmdef mutable struct ConflictingDefaultHistorySm end
    @statedef ConflictingDefaultHistorySm :ConflictingOwner
    @statedef ConflictingDefaultHistorySm :ConflictingA :ConflictingOwner
    @statedef ConflictingDefaultHistorySm :ConflictingB :ConflictingOwner
    @historydef ConflictingDefaultHistorySm :ConflictingOwner Hsm.DeepHistory() :ConflictingA
    @historydef ConflictingDefaultHistorySm :ConflictingOwner Hsm.DeepHistory() :ConflictingB
    @test_throws Hsm.HsmStateError ConflictingDefaultHistorySm()

    @hsmdef mutable struct DeclaredHistoryTestSm end
    @statedef DeclaredHistoryTestSm :DeclaredComposite
    @statedef DeclaredHistoryTestSm :DeclaredLeaf :DeclaredComposite
    @statedef DeclaredHistoryTestSm :DeclaredOutside
    @historydef DeclaredHistoryTestSm :DeclaredComposite

    @on_initial function (sm::DeclaredHistoryTestSm, ::Root)
        return Hsm.transition!(sm, :DeclaredOutside)
    end

    @on_initial function (sm::DeclaredHistoryTestSm, ::DeclaredComposite)
        return Hsm.transition!(sm, :DeclaredLeaf)
    end

    declared = DeclaredHistoryTestSm()
    @test Hsm.transition_history!(
        declared,
        :DeclaredComposite,
        Hsm.ShallowHistory(),
    ) === Hsm.EventHandled
    @test Hsm.current(declared) === :DeclaredLeaf

    @hsmdef mutable struct MultipleHistoryOwnersSm end
    @statedef MultipleHistoryOwnersSm :HistoryOwnerA
    @statedef MultipleHistoryOwnersSm :HistoryA1 :HistoryOwnerA
    @statedef MultipleHistoryOwnersSm :HistoryA2 :HistoryOwnerA
    @statedef MultipleHistoryOwnersSm :HistoryOwnerB
    @statedef MultipleHistoryOwnersSm :HistoryB1 :HistoryOwnerB
    @statedef MultipleHistoryOwnersSm :HistoryB2 :HistoryOwnerB
    @statedef MultipleHistoryOwnersSm :HistoryOutside
    @historydef MultipleHistoryOwnersSm :HistoryOwnerA
    @historydef MultipleHistoryOwnersSm :HistoryOwnerB

    @on_initial function (sm::MultipleHistoryOwnersSm, ::Root)
        return Hsm.transition!(sm, :HistoryOwnerA)
    end

    @on_initial function (sm::MultipleHistoryOwnersSm, ::HistoryOwnerA)
        return Hsm.transition!(sm, :HistoryA1)
    end

    @on_initial function (sm::MultipleHistoryOwnersSm, ::HistoryOwnerB)
        return Hsm.transition!(sm, :HistoryB1)
    end

    @on_event function (sm::MultipleHistoryOwnersSm, ::HistoryA1, ::AdvanceA, arg)
        return Hsm.transition!(sm, :HistoryA2)
    end

    @on_event function (sm::MultipleHistoryOwnersSm, ::HistoryOwnerA, ::EnterB, arg)
        return Hsm.transition!(sm, :HistoryOwnerB)
    end

    @on_event function (sm::MultipleHistoryOwnersSm, ::HistoryB1, ::AdvanceB, arg)
        return Hsm.transition!(sm, :HistoryB2)
    end

    @on_event function (sm::MultipleHistoryOwnersSm, ::HistoryOwnerB, ::LeaveB, arg)
        return Hsm.transition!(sm, :HistoryOutside)
    end

    @on_event function (sm::MultipleHistoryOwnersSm, ::HistoryOwnerA, ::LeaveA, arg)
        return Hsm.transition!(sm, :HistoryOutside)
    end

    @on_event function (sm::MultipleHistoryOwnersSm, ::HistoryOutside, ::RecallA, arg)
        return Hsm.transition_history!(sm, :HistoryOwnerA, Hsm.DeepHistory())
    end

    @on_event function (sm::MultipleHistoryOwnersSm, ::HistoryOutside, ::RecallB, arg)
        return Hsm.transition_history!(sm, :HistoryOwnerB, Hsm.DeepHistory())
    end

    multiple = MultipleHistoryOwnersSm()
    @test length(Hsm._history_storage(multiple)) == 2
    Hsm.dispatch!(multiple, :AdvanceA)
    Hsm.dispatch!(multiple, :EnterB)
    Hsm.dispatch!(multiple, :AdvanceB)
    Hsm.dispatch!(multiple, :LeaveB)

    @test Hsm.dispatch!(multiple, :RecallA) === Hsm.EventHandled
    @test Hsm.current(multiple) === :HistoryA2
    Hsm.dispatch!(multiple, :LeaveA)
    @test Hsm.dispatch!(multiple, :RecallB) === Hsm.EventHandled
    @test Hsm.current(multiple) === :HistoryB2

    @hsmdef mutable struct HistoryPerfSm end

    @statedef HistoryPerfSm :PerfComposite
    @statedef HistoryPerfSm :PerfBranch :PerfComposite
    @statedef HistoryPerfSm :PerfLeaf1 :PerfBranch
    @statedef HistoryPerfSm :PerfLeaf2 :PerfBranch
    @statedef HistoryPerfSm :PerfOutside

    @on_initial function (sm::HistoryPerfSm, ::Root)
        return Hsm.transition!(sm, :PerfComposite)
    end

    @on_initial function (sm::HistoryPerfSm, ::PerfComposite)
        return Hsm.transition!(sm, :PerfBranch)
    end

    @on_initial function (sm::HistoryPerfSm, ::PerfBranch)
        return Hsm.transition!(sm, :PerfLeaf1)
    end

    @on_event function (sm::HistoryPerfSm, ::PerfLeaf1, ::PerfNext, arg)
        return Hsm.transition!(sm, :PerfLeaf2)
    end

    @on_event function (sm::HistoryPerfSm, ::PerfLeaf2, ::PerfLeave, arg)
        return Hsm.transition!(sm, :PerfOutside)
    end

    @on_event function (sm::HistoryPerfSm, ::PerfOutside, ::PerfDeep, arg)
        return Hsm.transition_history!(
            sm,
            :PerfComposite,
            Hsm.DeepHistory(),
        )
    end

    @on_event function (sm::HistoryPerfSm, ::PerfOutside, ::PerfShallow, arg)
        return Hsm.transition_history!(
            sm,
            :PerfComposite,
            Hsm.ShallowHistory(),
        )
    end

    function history_cycle!(sm::HistoryPerfSm)
        Hsm.dispatch!(sm, :PerfNext)
        Hsm.dispatch!(sm, :PerfLeave)
        Hsm.dispatch!(sm, :PerfDeep)
        Hsm.dispatch!(sm, :PerfLeave)
        return Hsm.dispatch!(sm, :PerfShallow)
    end

    history_cycle_bytes(sm::HistoryPerfSm) = @allocated history_cycle!(sm)

    function dynamic_history_cycle!(sm::HistoryPerfSm)
        Hsm.transition!(sm, :PerfLeaf2)
        Hsm.transition!(sm, :PerfOutside)
        Hsm.transition_history!(sm, :PerfComposite, Hsm.DeepHistory())
        Hsm.transition!(sm, :PerfOutside)
        return Hsm.transition_history!(
            sm,
            :PerfComposite,
            Hsm.ShallowHistory(),
        )
    end

    dynamic_history_cycle_bytes(sm::HistoryPerfSm) =
        @allocated dynamic_history_cycle!(sm)

    perf = HistoryPerfSm()
    @test @inferred(history_cycle!(perf)) === Hsm.EventHandled
    @test Hsm.current(perf) === :PerfLeaf1
    history_cycle_bytes(perf)
    @test history_cycle_bytes(perf) == 0

    dynamic_perf = HistoryPerfSm()
    @test @inferred(dynamic_history_cycle!(dynamic_perf)) === Hsm.EventHandled
    @test Hsm.current(dynamic_perf) === :PerfLeaf1
    dynamic_history_cycle_bytes(dynamic_perf)
    @test dynamic_history_cycle_bytes(dynamic_perf) == 0

    # Static allocation evidence for the public runtime-Symbol boundary.  The
    # default `ignore_throw=true` excludes exception construction, matching the
    # steady-state contract, and there are no aliasing assumptions for this
    # mutable state-machine argument.
    #
    # AllocCheck 0.2 conservatively reports recursive generated calls reached
    # through nested initial transitions as DynamicDispatch on Julia 1.10 and
    # 1.12.  Optimized compiler output emits direct specialized calls for the
    # valid path, while the warmed correctness cycles above infer EventHandled
    # and allocate zero bytes.  Keep rejecting concrete allocation/runtime-call
    # sites without making the compiler-version-dependent dispatch count part
    # of the contract.
    @static if !Sys.iswindows()
        history_static_sites = AllocCheck.check_allocs(
            Hsm.dispatch!,
            (HistoryPerfSm, Symbol, Nothing),
        )
        @test all(
            site -> site isa AllocCheck.DynamicDispatch,
            history_static_sites,
        )
    end
end
