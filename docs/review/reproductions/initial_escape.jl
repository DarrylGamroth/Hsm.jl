using Hsm
@hsmdef mutable struct InitialEscapeSm end
@statedef InitialEscapeSm :Owner
@statedef InitialEscapeSm :Leaf :Owner
@statedef InitialEscapeSm :Outside
@on_initial function (sm::InitialEscapeSm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_initial function (sm::InitialEscapeSm, ::Owner)
    Hsm.transition!(sm, :Outside)
end
try
    sm = InitialEscapeSm()
    println("construction accepted escaping initial; current=", Hsm.current(sm))
catch error
    println("construction rejected: ", typeof(error))
end

using Test
@test_throws Hsm.HsmStateError InitialEscapeSm()
