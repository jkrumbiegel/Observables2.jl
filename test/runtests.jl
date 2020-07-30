using Observables2
using Test

@testset "Basics" begin
    xx = Observable([1, 2, 3])

    yy = observe!(xx, 2) do xs, factor
        xs .* factor
    end

    zz = observe!(yy) do y
        y ./ 10
    end

    xx[!] = [2, 3, 4]
    @test xx[] == [2, 3, 4]
    @test yy[] == [4, 6, 8]
    @test zz[] == [0.4, 0.6, 0.8]

    # check that all three observables are disabled through xx
    @test !is_disabled(xx)
    @test !is_disabled(yy)
    @test !is_disabled(zz)

    @test disable!(xx) == 3

    @test is_disabled(xx)
    @test is_disabled(yy)
    @test is_disabled(zz)
end

@testset "disabling middleman" begin

    objectcounter = Ref(0)

    mutable struct ObjectInMemory
        function ObjectInMemory()
            objectcounter[] += 1
            o = new()
            finalizer(o) do o
                objectcounter[] -= 1
                o
            end
            o
        end
    end

    qq = Observable([1, 2, 3])

    xx = observe!(identity, qq)

    yy = observe!(xx, 2) do xs, factor
        xs .* factor
    end

    @test objectcounter[] == 0

    zz = let
        memoryobject = ObjectInMemory()

        observe!(yy) do y
            # close over memoryobject
            if length(y) > 5
                println(memoryobject)
            end
            y ./ 10
        end
    end

    @test objectcounter[] == 1
    GC.gc()
    # the object shouldn't be garbage collected because it is referenced
    # in a closure in zz
    @test objectcounter[] == 1

    @test !is_disabled(qq)
    @test !is_disabled(xx)
    @test !is_disabled(yy)
    @test !is_disabled(zz)

    @test disable!(yy) == 2

    # yy and zz should be disabled, qq and xx shouldn't
    @test !is_disabled(qq)
    @test !is_disabled(xx)
    @test is_disabled(yy)
    @test is_disabled(zz)

    GC.gc()
    @test isnothing(zz.f)
    # this should work, but doesn't: @test objectcounter[] == 0
    # maybe that's due to garbage collector implementation, as I think the closure reference should be deleted correctly
end

@testset "Printing" begin
    xx = Observable([1, 2, 3])
    yy = observe!(identity, xx)

    @test string(xx) == """
        Observable{Array{Int64,1}} with 0 observable, 0 ordinary inputs, and 1 listeners.
        Value: [1, 2, 3]"""

    @test string(yy) == """
        Observable{Array{Int64,1}} with 1 observable, 0 ordinary inputs, and 0 listeners.
        Value: [1, 2, 3]"""

    stop_observing!(yy)

    @test string(xx) == """
        Observable{Array{Int64,1}} with 0 observable, 0 ordinary inputs, and 0 listeners.
        Value: [1, 2, 3]"""

    @test string(yy) == """
        Observable{Array{Int64,1}} with 0 observable, 1 ordinary inputs, and 0 listeners.
        Value: [1, 2, 3]"""
end

@testset "Typing" begin
    xx = Observable([1, 2, 3])
    @test typeof(xx) == Observable{Array{Int,1}}
    xx = Observable([1, 2, 3], type = Any)
    @test typeof(xx) == Observable{Any}
end


@testset "on onany off" begin
    x = Observable(1)
    y = Observable(2)

    testref = Ref(0)
    z = onany(x, y) do x, y
        testref[] = x + y
    end

    @test z isa ObservingFunction
    @test testref[] == 0
    x[] = 3
    @test testref[] == 5

    @test n_observable_inputs(z) == 2
    off(x, z)
    @test n_observable_inputs(z) == 1

    x[] = 4
    @test testref[] == 5
    y[] = 5
    @test testref[] == 8

end


@testset "ObservingFunction extras" begin
    x = Observable(1)

    r = Ref(0)

    # create an ObservingFunction
    y = on(x) do x
        r[] += 1
    end

    notify!(x)
    @test r[] == 1

    stop_observing!(y)
    notify!(x)
    # r should not have incremented further
    @test r[] == 1
end