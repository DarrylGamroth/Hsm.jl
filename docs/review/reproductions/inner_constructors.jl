using Test, Hsm

# Accepted remediation: reject unsupported inner constructors at expansion.
# Earlier diagnostic execution established that accepting this definition lets
# new(value) bypass initialization and leaves the private State fields undefined.
definition = :(Hsm.@hsmdef mutable struct InnerSm
    value::Int
    InnerSm(value::Int) = new(value)
end)
rejection = try
    macroexpand(Main, definition)
    nothing
catch error
    error
end
@show rejection
@test rejection isa Exception
@test occursin(r"inner.*constructor"i, sprint(showerror, rejection))
