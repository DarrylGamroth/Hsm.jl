using Hsm
@hsmdef mutable struct InitialChoiceOwnerSm
    log::Vector{Symbol}
end
@statedef InitialChoiceOwnerSm :Owner
@statedef InitialChoiceOwnerSm :A :Owner
@statedef InitialChoiceOwnerSm :B :Owner
@on_initial function (sm::InitialChoiceOwnerSm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_entry function (sm::InitialChoiceOwnerSm, ::Owner)
    push!(sm.log, :enter_owner)
end
@on_exit function (sm::InitialChoiceOwnerSm, ::Owner)
    push!(sm.log, :exit_owner)
end
@on_initial function (sm::InitialChoiceOwnerSm, ::Owner)
    @choice sm :Owner begin
        if true
            Hsm.transition!(sm, :A)
        else
            Hsm.transition!(sm, :B)
        end
    end
end
sm=InitialChoiceOwnerSm(Symbol[])
println("current=",Hsm.current(sm)," log=",sm.log)

using Test
@test sm.log == [:enter_owner]
