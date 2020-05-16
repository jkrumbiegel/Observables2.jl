using Observables2
using Test

@testset "Basics" begin
    xx = Observable([1, 2, 3])

    yy = observe(xx, 2) do xs, factor
        xs .* factor
    end

    zz = observe(yy) do y
        y ./ 10
    end

    xx[!] = [2, 3, 4]
    @test xx[] == [2, 3, 4]
    @test yy[] == [4, 6, 8]
    @test zz[] == [0.4, 0.6, 0.8]

    # check that all three observables are disabled through xx
    @test disable!(xx) == 3
end

@testset "Printing" begin
    xx = Observable([1, 2, 3])
    yy = observe(identity, xx)

    @test string(xx) == """
        Observable{Array{Int64,1}} with 0 observable, 0 ordinary inputs, and 1 observers.
        Value: [1, 2, 3]"""

    @test string(yy) == """
        Observable{Array{Int64,1}} with 1 observable, 0 ordinary inputs, and 0 observers.
        Value: [1, 2, 3]"""

    stop_observing!(yy)

    @test string(xx) == """
        Observable{Array{Int64,1}} with 0 observable, 0 ordinary inputs, and 0 observers.
        Value: [1, 2, 3]"""

    @test string(yy) == """
        Observable{Array{Int64,1}} with 0 observable, 1 ordinary inputs, and 0 observers.
        Value: [1, 2, 3]"""
end

@testset "Typing" begin
    xx = Observable([1, 2, 3])
    @test typeof(xx) == Observable{Array{Int,1}, Nothing}
    xx = Observable([1, 2, 3], type = Any)
    @test typeof(xx) == Observable{Any, Nothing}
end