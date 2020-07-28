# Observables2

[![Build Status](https://api.travis-ci.com/jkrumbiegel/Observables2.jl.svg?branch=master)](https://travis-ci.com/jkrumbiegel/Observables2.jl)
[![Codecov](https://codecov.io/gh/jkrumbiegel/Observables2.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jkrumbiegel/Observables2.jl)


A new take on observables. The following problems make working with observables from `Observables.jl` difficult:

# Disconnecting

In `Observables.jl`, every time you create an observable using `on`, a closure is created and stored in the listeners array of each "speaker" (the input of the listener). This closure keeps references to many objects, none of which can ever be garbage collected as long as the closure still exists.

To remove that closure and disable the observable, two things are needed in `Observables.jl`. The closure and the input observable. Then you can call `off(input, closure)`. Unfortunately, most often only the listener observable is actually stored, and the other two are not specifically tracked, making it nearly impossible to disconnect. This in turn means that many expensive objects are never garbage collected.

## The fix

In `Observables2.jl`, an observable doesn't only store a vector of listeners, it also stores a vector of inputs. The inputs can be of any type, the listeners can only be observables.

```julia
julia> xx = Observable([1, 2, 3])

# Observable{Array{Int64,1}} with 0 observable, 0 ordinary inputs, and 0 observers.
# Value: [1, 2, 3]

julia> yy = observe(xx, 2) do xs, factor
               xs .* factor
           end
# Observable{Array{Int64,1}} with 1 observable, 1 ordinary inputs, and 0 observers.
# Value: [2, 4, 6]

julia> xx

# Observable{Array{Int64,1}} with 0 observable, 0 ordinary inputs, and 1 observers.
# Value: [2, 3, 4]
```

You can deactivate an observable (make it stop listening) by calling `stop_observing!`.

There are two variants: specifically stopping to observe one observable, or stopping to observe all inputs (if there are multiple). Either `stop_observing!(observable, input)` or `stop_observing!(observable)`. For each disabled input, the input entry in the observable is replaced with the last value of that input. This means the closure of the observable will still work, disabled inputs will just never change again.

```julia
julia> stop_observing!(yy)

julia> yy
# Observable{Array{Int64,1}} with 0 observable, 2 ordinary inputs, and 0 observers.
# Value: [4, 6, 8]

julia> xx
# Observable{Array{Int64,1}} with 0 observable, 0 ordinary inputs, and 0 observers.
# Value: [2, 3, 4]
```

## Recursive disabling

That leads to another benefit: An observable that only has disabled inputs can never change again, unless when directly mutated. Because direct mutation is often not possible anyway, because the observable has gone out of scope, we might as well disable this observable in all input vectors of all listeners. Then, in turn, these listeners might all have no active inputs left, can be disabled, and so on. This means a whole tree of observables can be disabled by disabling only the top node.

# Trigger on change

In `Observables.jl`, there is no built-in way to only trigger a change if the new observable value is actually different from the stored value. It can save quite a bit of computation if a trigger chain stops when no new value is generated anymore.

## The fix

In `Observables2.jl`, every observable has the field `onlynew`. If that is set to `true`, by default the assignment of the same value as currently stored will not trigger listeners, unless manually overridden.

## Override syntax

In `Observables2.jl`, an observable can be forced to trigger on change with the `!` syntax. This can sometimes be necessary if an observable should forward events no matter what value arrived.

```julia
o = Observable(1, onlynew = true)

o[] = 1 # nothing happens with the listeners
o[!] = 1 # the listeners get triggered even though the value is the same
```
