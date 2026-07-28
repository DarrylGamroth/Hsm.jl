module DiagramFixture

using Hsm

export DiagramTestSm

@hsmdef mutable struct DiagramTestSm
    choose_final::Bool
end

@statedef DiagramTestSm :Operating
@statedef DiagramTestSm :Idle :Operating
@statedef DiagramTestSm :Busy :Operating
@finaldef DiagramTestSm :Done :Operating
@statedef DiagramTestSm :Outside
@terminatedef DiagramTestSm :Stopped
@historydef DiagramTestSm :Operating Hsm.DeepHistory() :Busy
@historydef DiagramTestSm :Operating Hsm.ShallowHistory() :Idle

@on_initial function (sm::DiagramTestSm, ::Root)
    return Hsm.transition!(sm, :Operating)
end

@on_initial function (sm::DiagramTestSm, ::Operating)
    return Hsm.transition!(sm, :Idle)
end

@on_event function (sm::DiagramTestSm, ::Operating, ::Reset, _)
    return Hsm.transition!(sm, :Idle)
end

@on_event function (sm::DiagramTestSm, ::Idle, ::Work, _)
    return Hsm.transition!(sm, :Busy) do
        sm.choose_final = false
    end
end

@on_event function (sm::DiagramTestSm, ::Busy, ::Leave, _)
    return Hsm.transition!(sm, :Outside)
end

@on_event function (sm::DiagramTestSm, ::Busy, ::Retry, _)
    return Hsm.transition!(sm, :Busy)
end

# A handler with no statically named edge cannot be classified safely as an
# internal Transition rather than an unhandled path, so it is omitted.
@on_event function (sm::DiagramTestSm, ::Busy, ::Ping, _)
    return Hsm.EventHandled
end

@on_event function (sm::DiagramTestSm, ::Outside, ::Recall, _)
    return Hsm.transition_history!(
        sm,
        :Operating,
        Hsm.DeepHistory(),
    )
end

@on_event function (sm::DiagramTestSm, ::Outside, ::Choose, _)
    return @choice sm :Operating begin
        sm.choose_final = !sm.choose_final
        if sm.choose_final
            Hsm.transition!(sm, :Done) do
                sm.choose_final = false
            end
        else
            Hsm.transition!(sm, :Busy)
        end
    end
end

@on_event function (sm::DiagramTestSm, ::Outside, ::Stop, _)
    return Hsm.transition!(sm, :Stopped)
end

@on_completion function (sm::DiagramTestSm, ::Operating)
    return Hsm.transition!(sm, :Outside)
end

@on_history_default function (
    sm::DiagramTestSm,
    ::Operating,
    ::DeepHistory,
)
    sm.choose_final = false
    return nothing
end

end
