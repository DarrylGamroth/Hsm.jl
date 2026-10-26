using Test, Hsm

@testset "README abstract-machine example" begin
    readme = read(joinpath(pkgdir(Hsm), "README.md"), String)
    blocks = [match.captures[1] for match in eachmatch(r"```julia\n(.*?)```"s, readme)]
    code = only(filter(block -> occursin("@abstracthsmdef VehicleController", block), blocks))
    example = Module(:ReadmeAbstractExample)
    Core.eval(example, Meta.parseall(code))
    car, truck = getfield(example, :vehicles)
    @test current(car) === :Moving
    @test current(truck) === :Moving
    @test car.speed == 20.0
    @test car.fuel == 98.0
    @test truck.speed ≈ 20.0 / 6.0
    @test truck.cargo == 5000.0
end
