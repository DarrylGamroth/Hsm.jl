using Test
using Hsm

@testset "Runnable examples" begin
    project_file = Base.active_project()
    @test project_file !== nothing
    project_dir = dirname(project_file)
    repository = pkgdir(Hsm)

    for filename in (
        "simplest_example.jl",
        "abstract_example.jl",
        "example.jl",
        "pseudostates_example.jl",
    )
        @testset "$filename" begin
            path = joinpath(repository, "example", filename)
            command = `$(Base.julia_cmd()) --startup-file=no --project=$project_dir $path`
            output = IOBuffer()
            process = run(pipeline(
                ignorestatus(command),
                stdout=output,
                stderr=output,
            ))
            rendered = String(take!(output))
            if !success(process)
                @error "Example failed" filename rendered
            end
            @test success(process)
            @test !isempty(strip(rendered))
            if filename == "pseudostates_example.jl"
                @test occursin("Completed lifecycle: true", rendered)
                @test occursin("Terminated lifecycle: true", rendered)
            end
        end
    end
end
