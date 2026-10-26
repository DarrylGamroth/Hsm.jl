using Test, Hsm, Profile, InteractiveUtils

# Loading another valid machine must not change this machine's allocation budget.
include(joinpath(pkgdir(Hsm), "test", "test_core.jl"))

module AllocationRepro
using Hsm
@hsmdef mutable struct Machine
    count::Int
end
@statedef Machine :Parent
@statedef Machine :Leaf :Parent
@on_initial function(sm::Machine, ::Root)
    transition!(sm, :Parent)
end
@on_initial function(sm::Machine, ::Parent)
    transition!(sm, :Leaf)
end
@on_event function(sm::Machine, ::Leaf, ::Ping, data::Int)
    sm.count += data
    EventHandled
end
ping!(sm::Machine) = dispatch!(sm, :Ping, 1)
bytes(sm::Machine) = @allocated ping!(sm)
allocations(sm::Machine) = @allocations ping!(sm)
seconds(sm::Machine) = @elapsed ping!(sm)
end
sm = AllocationRepro.Machine(0)
for _ in 1:10
    AllocationRepro.ping!(sm)
    AllocationRepro.bytes(sm)
    AllocationRepro.allocations(sm)
    AllocationRepro.seconds(sm)
end
prior = sm.count
result = AllocationRepro.ping!(sm)
@test result === EventHandled
@test current(sm) === :Leaf
@test sm.count == prior + 1
bytes = AllocationRepro.bytes(sm)
allocations = AllocationRepro.allocations(sm)
minimum_seconds = minimum(AllocationRepro.seconds(sm) for _ in 1:1000)
println((julia=VERSION, platform=Sys.MACHINE, threads=Threads.nthreads(), signature="dispatch!(::AllocationRepro.Machine, ::Symbol, ::Int64)", bytes=bytes, allocations=allocations, minimum_seconds=minimum_seconds, valsplit_path=pathof(ValSplit)))
if "--profile" in ARGS
    @code_warntype Hsm.on_event!(sm, :Leaf, :Ping, 1)
    Profile.Allocs.clear()
    Profile.Allocs.@profile sample_rate=1 AllocationRepro.ping!(sm)
    for item in Profile.Allocs.fetch().allocs
        println("ALLOCATION ", item.type, " ", item.size)
        for frame in item.stacktrace
            occursin("Hsm.jl", string(frame.file)) && println(frame)
        end
    end
else
    @test bytes == 0
end
