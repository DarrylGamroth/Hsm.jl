"""
A complete example of Hsm.jl's supported UML control vertices:

- an explicit deep-history default Transition;
- a choice Pseudostate with statically named targets;
- a nested FinalState and its completion Transition;
- a top-level FinalState and lifecycle inspection; and
- a terminate Pseudostate.

Run from the repository root with:

    julia --project=. example/pseudostates_example.jl
"""

using Hsm

@hsmdef mutable struct DocumentWorkflow
    log::Vector{Symbol}
end

# One implicit top-level Region, with a nested Processing Region.
@statedef DocumentWorkflow :WorkflowIdle
@statedef DocumentWorkflow :WorkflowProcessing
@statedef DocumentWorkflow :WorkflowReview :WorkflowProcessing
@statedef DocumentWorkflow :WorkflowApproved :WorkflowProcessing
@statedef DocumentWorkflow :WorkflowRejected :WorkflowProcessing
@finaldef DocumentWorkflow :WorkflowProcessingDone :WorkflowProcessing
@statedef DocumentWorkflow :WorkflowArchived
@finaldef DocumentWorkflow :WorkflowDone
@terminatedef DocumentWorkflow :WorkflowTerminate

# If Processing has no recorded history, Resume takes this explicit default
# edge instead of Processing's ordinary initial transition.
@historydef DocumentWorkflow :WorkflowProcessing Hsm.DeepHistory() :WorkflowReview

@on_history_default function (
    sm::DocumentWorkflow,
    ::WorkflowProcessing,
    ::DeepHistory,
)
    push!(sm.log, :history_default_effect)
    return nothing
end

@on_initial function (sm::DocumentWorkflow, ::Root)
    return Hsm.transition!(sm, :WorkflowIdle)
end

@on_initial function (sm::DocumentWorkflow, ::WorkflowProcessing)
    return Hsm.transition!(sm, :WorkflowReview)
end

@on_entry function (sm::DocumentWorkflow, state::Any)
    push!(sm.log, Symbol(:enter_, state))
    return nothing
end

@on_exit function (sm::DocumentWorkflow, state::Any)
    push!(sm.log, Symbol(:exit_, state))
    return nothing
end

@on_event function (sm::DocumentWorkflow, ::WorkflowIdle, ::Resume, arg)
    return Hsm.transition_history!(
        sm,
        :WorkflowProcessing,
        Hsm.DeepHistory(),
    ) do
        push!(sm.log, :resume_effect)
    end
end

@on_event function (
    sm::DocumentWorkflow,
    ::WorkflowReview,
    ::Decide,
    approved::Bool,
)
    return @choice sm :WorkflowProcessing begin
        push!(sm.log, :choice_incoming_effect)
        if approved
            Hsm.transition!(sm, :WorkflowApproved) do
                push!(sm.log, :approved_effect)
            end
        else
            Hsm.transition!(sm, :WorkflowRejected) do
                push!(sm.log, :rejected_effect)
            end
        end
    end
end

# This ancestor handler records the active Processing leaf as deep history.
@on_event function (sm::DocumentWorkflow, ::WorkflowProcessing, ::Suspend, arg)
    return Hsm.transition!(sm, :WorkflowIdle)
end

@on_event function (sm::DocumentWorkflow, ::WorkflowRejected, ::Retry, arg)
    return Hsm.transition!(sm, :WorkflowReview)
end

@on_event function (sm::DocumentWorkflow, ::WorkflowApproved, ::Finish, arg)
    return Hsm.transition!(sm, :WorkflowProcessingDone)
end

# The nested FinalState completes WorkflowProcessing and generates this event.
@on_completion function (sm::DocumentWorkflow, ::WorkflowProcessing)
    return Hsm.transition!(sm, :WorkflowArchived)
end

@on_event function (sm::DocumentWorkflow, ::WorkflowArchived, ::Complete, arg)
    return Hsm.transition!(sm, :WorkflowDone)
end

@on_event function (sm::DocumentWorkflow, ::WorkflowIdle, ::Abort, arg)
    return Hsm.transition!(sm, :WorkflowTerminate)
end

function successful_workflow()
    sm = DocumentWorkflow(Symbol[])
    @assert Hsm.isrunning(sm)
    @assert Hsm.current(sm) === :WorkflowIdle

    # There is no stored history yet, so the explicit default edge is used.
    Hsm.dispatch!(sm, :Resume)
    @assert Hsm.current(sm) === :WorkflowReview
    @assert count(==(:history_default_effect), sm.log) == 1

    # Runtime data selects one of two static choice edges.
    Hsm.dispatch!(sm, :Decide, true)
    @assert Hsm.current(sm) === :WorkflowApproved

    # Leave and restore Processing. Deep history returns directly to Approved
    # without invoking the default-history effect a second time.
    Hsm.dispatch!(sm, :Suspend)
    @assert Hsm.current(sm) === :WorkflowIdle
    Hsm.dispatch!(sm, :Resume)
    @assert Hsm.current(sm) === :WorkflowApproved
    @assert count(==(:history_default_effect), sm.log) == 1

    # The nested FinalState triggers WorkflowProcessing's completion
    # Transition to Archived. The top-level FinalState then completes the
    # machine and rejects further execution.
    Hsm.dispatch!(sm, :Finish)
    @assert Hsm.current(sm) === :WorkflowArchived
    Hsm.dispatch!(sm, :Complete)
    @assert Hsm.current(sm) === :WorkflowDone
    @assert Hsm.iscomplete(sm)
    @assert !Hsm.isrunning(sm)
    return sm
end

function terminated_workflow()
    sm = DocumentWorkflow(Symbol[])
    Hsm.dispatch!(sm, :Abort)
    @assert Hsm.isterminated(sm)
    @assert !Hsm.isrunning(sm)
    @assert Hsm.current(sm) === :Root
    return sm
end

function main(args)
    completed = successful_workflow()
    terminated = terminated_workflow()
    println("Completed lifecycle: ", Hsm.iscomplete(completed))
    println("Terminated lifecycle: ", Hsm.isterminated(terminated))
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
