using Test
using Hsm
using ValSplit

@testset "Edge Cases and Error Handling" begin

    @testset "Empty struct handling" begin
        @eval begin
            @hsmdef mutable struct EmptyTestStruct
            end
        end

        @test length(fieldnames(EmptyTestStruct)) == 2  # 0 original + 2 generated

        # Should be able to construct with no arguments
        obj = EmptyTestStruct()
        empty_fields = fieldnames(EmptyTestStruct)
        @test getfield(obj, empty_fields[1]) == :Root
        @test getfield(obj, empty_fields[2]) == :Root
    end

    @testset "Struct with only type parameters" begin
        @eval begin
            @hsmdef mutable struct OnlyTypeParams{T,U}
            end
        end

        @test length(fieldnames(OnlyTypeParams)) == 2  # 0 original + 2 generated

        # For parametric types, we need to construct with explicit types and all fields
        obj = OnlyTypeParams{Int,String}(:Root, :Root)
        only_fields = fieldnames(OnlyTypeParams)
        @test getfield(obj, only_fields[1]) == :Root
        @test getfield(obj, only_fields[2]) == :Root
    end

    @testset "Single field variations" begin
        # Test different single field types
        @eval begin
            @hsmdef mutable struct SingleInt
                value::Int
            end

            @hsmdef mutable struct SingleString
                text::String
            end

            @hsmdef mutable struct SingleVector{T}
                items::Vector{T}
            end
        end

        obj1 = SingleInt(42)
        @test obj1.value == 42
        single_int_fields = fieldnames(SingleInt)
        @test getfield(obj1, single_int_fields[end-1]) == :Root
        @test getfield(obj1, single_int_fields[end]) == :Root

        obj2 = SingleString("hello")
        @test obj2.text == "hello"
        single_string_fields = fieldnames(SingleString)
        @test getfield(obj2, single_string_fields[end-1]) == :Root
        @test getfield(obj2, single_string_fields[end]) == :Root

        obj3 = SingleVector([1.0, 2.0, 3.0])
        @test obj3.items == [1.0, 2.0, 3.0]
        single_vector_fields = fieldnames(SingleVector)
        @test getfield(obj3, single_vector_fields[end-1]) == :Root
        @test getfield(obj3, single_vector_fields[end]) == :Root
    end

    @testset "Immutable struct support" begin
        @eval begin
            @hsmdef mutable struct ImmutableStruct
                x::Int
                y::String
            end
        end

        @test hasfield(ImmutableStruct, :x)
        @test hasfield(ImmutableStruct, :y)
        @test length(fieldnames(ImmutableStruct)) == 4  # 2 original + 2 generated

        obj = ImmutableStruct(100, "immutable")
        @test obj.x == 100
        @test obj.y == "immutable"

        immutable_fields = fieldnames(ImmutableStruct)
        @test getfield(obj, immutable_fields[end-1]) == :Root
        @test getfield(obj, immutable_fields[end]) == :Root
    end

    @testset "Fields with complex types" begin
        @eval begin
            @hsmdef mutable struct ComplexFieldTypes
                dict_field::Dict{String,Int}
                tuple_field::Tuple{Int,String,Float64}
                union_field::Union{Int,String}
                function_field::Function
                array_field::Array{Float64,2}
            end
        end

        test_dict = Dict("a" => 1, "b" => 2)
        test_tuple = (42, "test", 3.14)
        test_function = x -> x^2
        test_array = [1.0 2.0; 3.0 4.0]

        obj = ComplexFieldTypes(test_dict, test_tuple, 42, test_function, test_array)
        @test obj.dict_field == test_dict
        @test obj.tuple_field == test_tuple
        @test obj.union_field == 42
        @test obj.function_field(5) == 25
        @test obj.array_field == test_array

        complex_fields = fieldnames(ComplexFieldTypes)
        @test getfield(obj, complex_fields[end-1]) == :Root
        @test getfield(obj, complex_fields[end]) == :Root

        # Test with Union field as String
        obj2 = ComplexFieldTypes(test_dict, test_tuple, "string", test_function, test_array)
        @test obj2.union_field == "string"
        @test getfield(obj2, complex_fields[end-1]) == :Root
        @test getfield(obj2, complex_fields[end]) == :Root
    end

    @testset "Multiple type constraints" begin
        @eval begin
            @hsmdef mutable struct MultipleConstraints{T<:Number, U<:AbstractString, V<:AbstractVector{T}}
                number::T
                text::U
                vector::V
            end
        end

        obj = MultipleConstraints(3.14, "test", [1.0, 2.0])
        @test obj.number == 3.14
        @test obj.text == "test"
        @test obj.vector == [1.0, 2.0]

        constraints_fields = fieldnames(MultipleConstraints)
        @test getfield(obj, constraints_fields[end-1]) == :Root
        @test getfield(obj, constraints_fields[end]) == :Root
    end

    @testset "Nested struct definitions" begin
        # Define inner struct first
        struct InnerStruct
            inner_value::String
        end

        # Test that @hsmdef works with structs that reference other structs
        @hsmdef mutable struct OuterStruct
            value::Int
            inner::InnerStruct
        end

        @test hasfield(OuterStruct, :value)
        @test hasfield(OuterStruct, :inner)
        @test length(fieldnames(OuterStruct)) == 4  # 2 original + 2 generated

        # Inner struct should not have the additional fields
        @test hasfield(InnerStruct, :inner_value)
        @test length(fieldnames(InnerStruct)) == 1  # Only original field

        inner = InnerStruct("inner test")
        obj = OuterStruct(42, inner, :Root, :Root)
        @test obj.value == 42
        @test obj.inner.inner_value == "inner test"

        outer_fields = fieldnames(OuterStruct)
        @test getfield(obj, outer_fields[end-1]) == :Root
        @test getfield(obj, outer_fields[end]) == :Root

        # Test additional constructor
        obj2 = OuterStruct(100, inner)
        @test obj2.value == 100
        @test obj2.inner.inner_value == "inner test"
        @test getfield(obj2, outer_fields[end-1]) == :Root
        @test getfield(obj2, outer_fields[end]) == :Root
    end

    @testset "Performance characteristics" begin
        # Test that the macro doesn't introduce significant overhead
        @eval begin
            @hsmdef mutable struct PerformanceTest
                x::Int
                y::Float64
            end
        end

        # Test construction performance
        @test @elapsed(begin
            for i in 1:1000
                PerformanceTest(i, Float64(i))
            end
        end) < 0.1  # Should be very fast

        # Test field access performance
        obj = PerformanceTest(42, 3.14)
        perf_fields = fieldnames(PerformanceTest)
        @test @elapsed(begin
            for i in 1:10000
                _ = obj.x + obj.y + (getfield(obj, perf_fields[end-1]) == :Root ? 1 : 0)
            end
        end) < 0.1  # Should be very fast
    end
end
