using Test
using Hsm
using ValSplit

# Define abstract types needed for tests
abstract type AbstractType end

@testset "Macro Expansion Comparison Tests" begin

    @testset "Plain struct expansion test" begin
        # Test the exact example from the documentation
        expansion = @macroexpand @hsmdef mutable struct MyStruct{T,C<:Real} <: AbstractType
            counter::C
            status::String
            data::Vector{T}
        end

        # The expansion should be a block containing struct definition and constructor
        @test expansion isa Expr
        @test expansion.head == :block

        # Extract components
        struct_def = nothing
        constructor_def = nothing

        function find_struct_in_block(block_expr)
            if block_expr isa Expr
                for item in block_expr.args
                    if item isa Expr
                        if item.head == :struct
                            return item
                        elseif item.head == :block
                            # Recursively search nested blocks
                            result = find_struct_in_block(item)
                            if result !== nothing
                                return result
                            end
                        end
                    end
                end
            end
            return nothing
        end

        for item in expansion.args
            if item isa Expr
                if item.head == :struct
                    struct_def = item
                elseif item.head == :function
                    constructor_def = item
                elseif item.head == :block
                    # The struct might be inside a block
                    if struct_def === nothing
                        struct_def = find_struct_in_block(item)
                    end
                elseif item.head == :macrocall && length(item.args) >= 3
                    # Handle Base.@__doc__ wrapper
                    if item.args[1] == GlobalRef(Core, Symbol("@__doc__"))
                        wrapped = item.args[3]
                        if wrapped isa Expr
                            if wrapped.head == :struct
                                struct_def = wrapped
                            elseif wrapped.head == :block
                                # The struct is inside a block
                                struct_def = find_struct_in_block(wrapped)
                            end
                        end
                    end
                end
            end
        end

        @test struct_def !== nothing
        @test constructor_def !== nothing

        # Verify struct has the additional fields (original 3 + 2 new = 5 total)
        struct_body = struct_def.args[3]
        field_expressions = filter(x -> x isa Expr && x.head == :(::), struct_body.args)
        field_names = [expr.args[1] for expr in field_expressions]

        @test :counter in field_names
        @test :status in field_names
        @test :data in field_names
        @test length(field_names) == 5  # 3 original + 2 generated fields

        # Check that the last two fields are Symbol type
        @test field_expressions[end-1].args[2] == :Symbol
        @test field_expressions[end].args[2] == :Symbol

        # Verify constructor signature
        @test constructor_def.args[1].args[1] == :MyStruct
        # Should accept 3 arguments (Vararg{Any,3})
        vararg_type = constructor_def.args[1].args[2].args[2]
        @test vararg_type.args[1] == :Vararg
        @test vararg_type.args[3] == 3
    end

    @testset "@kwdef integration test" begin
        # Test that @hsmdef works correctly with @kwdef
        abstract type TestAbstractType end

        # First test pure @kwdef behavior
        kwdef_expansion = @macroexpand Base.@kwdef mutable struct KwDefOnly{T,C<:Real} <: TestAbstractType
            counter::C
            status::String = "idle"
            data::Vector{T} = T[]
        end

        # Now test @hsmdef with @kwdef
        combined_expansion = @macroexpand @hsmdef Base.@kwdef mutable struct KwDefWithInsert{T,C<:Real} <: TestAbstractType
            counter::C
            status::String = "idle"
            data::Vector{T} = T[]
        end

        @test combined_expansion isa Expr

        # Extract all function definitions from the combined expansion
        functions = []
        struct_def = nothing

        function extract_from_block(expr)
            if expr isa Expr
                if expr.head == :block
                    for item in expr.args
                        extract_from_block(item)
                    end
                elseif expr.head == :function
                    push!(functions, expr)
                elseif expr.head == :struct
                    struct_def = expr
                end
            end
        end

        extract_from_block(combined_expansion)

        @test struct_def !== nothing
        @test length(functions) >= 3  # Should have at least 3 constructors

        # Check that we have the additional constructor from @hsmdef
        has_vararg_constructor = false
        for func in functions
            if func.args[1] isa Expr && length(func.args[1].args) >= 2
                if func.args[1].args[2] isa Expr &&
                   func.args[1].args[2].head == :(::) &&
                   func.args[1].args[2].args[2] isa Expr &&
                   func.args[1].args[2].args[2].args[1] == :Vararg
                    has_vararg_constructor = true
                    # Should be Vararg{Any,3} for 3 original fields
                    @test func.args[1].args[2].args[2].args[3] == 3
                end
            end
        end
        @test has_vararg_constructor

        # Test that the struct has the right number of fields (3 original + 2 generated = 5)
        all_fields = filter(x -> x isa Expr && x.head == :(::), struct_def.args[3].args)
        @test length(all_fields) == 5
    end

    @testset "Field counting accuracy" begin
        # Test various field configurations to ensure correct counting

        # Single field
        exp1 = @macroexpand @hsmdef mutable struct SingleField
            x::Int
        end

        # Extract constructor and verify it takes 1 argument
        func1 = nothing
        for item in exp1.args
            if item isa Expr && item.head == :function
                func1 = item
                break
            end
        end
        @test func1 !== nothing
        vararg_count1 = func1.args[1].args[2].args[2].args[3]
        @test vararg_count1 == 1

        # Multiple fields
        exp2 = @macroexpand @hsmdef mutable struct MultipleFields
            a::Int
            b::String
            c::Float64
            d::Bool
        end

        func2 = nothing
        for item in exp2.args
            if item isa Expr && item.head == :function
                func2 = item
                break
            end
        end
        @test func2 !== nothing
        vararg_count2 = func2.args[1].args[2].args[2].args[3]
        @test vararg_count2 == 4
    end

    @testset "Parametric types with complex constraints" begin
        # Test parametric struct with multiple type parameters and constraints
        expansion = @macroexpand @hsmdef mutable struct ComplexStruct{T<:Number,U,V<:AbstractVector{U}}
            primary::T
            secondary::U
            collection::V
        end

        @test expansion isa Expr

        # Verify we can create instances with the correct behavior
        @eval $expansion

        # Get the actual field names dynamically
        all_field_names = fieldnames(ComplexStruct)
        @test length(all_field_names) == 5  # 3 original + 2 generated

        # Test constructor with original arguments
        obj = ComplexStruct(42, "test", ["a", "b", "c"])
        @test obj.primary == 42
        @test obj.secondary == "test"
        @test obj.collection == ["a", "b", "c"]

        # Test that the last two fields are set to :Root
        @test getfield(obj, all_field_names[end-1]) == :Root
        @test getfield(obj, all_field_names[end]) == :Root
    end
end
