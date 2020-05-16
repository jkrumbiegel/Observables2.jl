module Observables2

export Observable
export observe
export stop_observing!
export disable!

mutable struct Observable{V, F<:Union{Function, Nothing}}
    value::V
    f::F
    inputs::Vector{Any}
    observers::Vector{Observable}
    onlynew::Bool

    Observable(value::V, f::F, inputs, observers, onlynew) where {V, F} = new{V,F}(value, f, inputs, observers, onlynew)

    Observable{V}(value, f::F, inputs, observers, onlynew) where {V, F} = new{V,F}(value, f, inputs, observers, onlynew)
end

# if we allow replacement of active observables with their values to inactivate them
# there needs to be a wrapper type to distinguish between an observable that is registered
# and an observable that is just a value
struct RegisteredObservable
    o::Observable
end

Observable(v; onlynew = false, type = nothing) =
    Observable{isnothing(type) ? typeof(v) : type}(v, nothing, [], Observable[], onlynew)

get_registered_value(r::RegisteredObservable) = r.o.value
get_registered_value(any) = any

function Base.setindex!(obs::Observable, value, ::typeof(!))
    obs.value = value
    for o in obs.observers
        new_value = o.f((get_registered_value(input) for input in o.inputs)...)
        set_new_value!(o, new_value)
    end
    obs
end

function set_new_value!(o::Observable, value)
    if !o.onlynew || o.value != value
        o[!] = value
    end
end

function Base.setindex!(obs::Observable, value)
    set_new_value!(obs, value)
end

Base.getindex(obs::Observable) = obs.value

function register!(with::Observable, o::Observable)
    if o in with.observers
        error("Observable already registered as observer.")
    end
    push!(with.observers, o)
end

get_value(any) = any
get_value(o::Observable) = o.value

wrap_register(any) = any
wrap_register(o::Observable) = RegisteredObservable(o)

unwrap_register(any) = any
unwrap_register(ro::RegisteredObservable) = ro.o

function observe(f::Function, inputs...; onlynew = false, type::Union{Type, Nothing} = nothing)
    # compute first value
    value = f((get_value(input) for input in inputs)...)
    # make a new observer that tracks who he observes but isn't yet registered with the other observers
    if isnothing(type)
        observable = Observable(value, f,
            Any[wrap_register(i) for i in inputs], Observable[], onlynew)
    else
        observable = Observable{type}(value, f,
            Any[wrap_register(i) for i in inputs], Observable[], onlynew)
    end
    # register this observable
    for o in inputs
        if o isa Observable
            register!(o, observable)
        end
    end
    observable
end

"""
    stop_observing!(observer::Observable, input::Observable)

Replace the `input` `Observable` in the input vector of the `observer` with its value
and remove the `observer` from the `observers` of the `input` `Observable`.
"""
function stop_observing!(observer::Observable, input::Observable)
    # delete input in observer
    inputindex = findfirst(==(RegisteredObservable(input)), observer.inputs)
    if isnothing(inputindex)
        error("Observable was not registered as an input.")
    end

    observerindex = findfirst(==(observer), input.observers)
    if isnothing(observerindex)
        error("Observable was not registered as an observer.")
    end

    observer.inputs[inputindex] = get_value(input)
    deleteat!(input.observers, observerindex)
end

function stop_observing!(observer::Observable, input)
    # do nothing
end

"""
    stop_observing!(observer::Observable)
    
Replace all `Observable`s in the input vector of the `observer` with their values
and remove the `observer` from the `observers` of each of these `Observable`s.
"""
function stop_observing!(observer::Observable)
    for input in observer.inputs
        stop_observing!(observer, unwrap_register(input))
    end
end

n_ordinary_inputs(o::Observable) = sum((!isa).(o.inputs, RegisteredObservable))
n_observable_inputs(o::Observable) = sum(isa.(o.inputs, RegisteredObservable))

function Base.show(io::IO, o::Observable{V}) where V

    n_observable = n_observable_inputs(o)
    n_ordinary = n_ordinary_inputs(o)
    n_observers = length(o.observers)

    str = "Observable{$V} with $n_observable observable, $n_ordinary ordinary inputs, and $n_observers observers."
    println(io, str)
    print(io, "Value: $(o.value)")
    nothing
end

"""
    disable!(o::Observable; recursive = true)

Make all observers of `o` stop observing it.
If `recursive` is `true`, all observers that don't have any `Observable` inputs
left after stopping are also disabled.

Returns the number of all disabled `Observable`s.
"""
function disable!(o::Observable; recursive = true)
    n_disabled = 1
    for observer in o.observers
        stop_observing!(observer, o)
        # if the observer doesn't have any inputs left that are observables
        # we can disable it as well, because it will never be triggered again
        if recursive && n_observable_inputs(observer) == 0
            n_disabled += disable!(observer; recursive = true)
        end
    end
    n_disabled
end

end # module
