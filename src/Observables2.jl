module Observables2


export Observable
export observe!
export stop_observing!
export disable!
export is_disabled
export listeners
export notify!
export to_value
export on
export off
export onany
export connect! # obsid, async_latest, throttle
export NoValue
export n_ordinary_inputs
export n_observable_inputs


abstract type AbstractObservable{T} end

# this struct is used to parameterize Observables without a value
# before, you would use `on` and just retrieve a closure that would be
# stored in the listeners array
# but a closure doesn't keep a reference to its inputs, which is why it's
# harder to disconnect
struct NoValue end


mutable struct Observable{V} <: AbstractObservable{V}
    val::V
    f::Any
    inputs::Vector{Any}
    listeners::Vector{<:AbstractObservable}
    onlynew::Bool
end


# creating an observable from a value only
# no inputs or listeners are set up
Observable(v; onlynew = false, type = nothing) =
    Observable{isnothing(type) ? typeof(v) : type}(v, nothing, [], Observable[], onlynew)

Observable{T}(v) where T = Observable(v; type = T)

# function Base.map(f, o::AbstractObservable, os...)
#     observe!(f, o, os...)
# end

Base.eltype(::AbstractObservable{T}) where {T} = T





# triggering an observable again with its current value
function notify!(o::Observable)
    o[!] = o[]
end


# extracting a value from an observable
to_value(o::Observable) = o.val
to_value(x) = x

listeners(o::Observable) = o.listeners


# function Base.copy(o::Observable{T}) where T
#     oc = Observable{T}(o.val)
#     on(o) do o
#         oc[] = o
#     end
#     oc
# end

function connect!(o1::Observable, o2::Observable)
    error("not implemented")
end

# if we allow replacement of active observables with their values to inactivate them
# there needs to be a wrapper type to distinguish between an observable that is registered
# and an observable that is just a value
struct RegisteredObservable
    o::Observable
end


get_registered_value(r::RegisteredObservable) = r.o.val
get_registered_value(any) = any

function Base.setindex!(obs::Observable, value, ::typeof(!))
    obs.val = value
    for o in obs.listeners
        # NoValue observables don't get a new value set, just their function called
        if o isa Observable{NoValue}
            # call the stored function with the values of registered observables
            # or the inputs directly
            o.f((get_registered_value(input) for input in o.inputs)...)
        else
            # call the stored function with the values of registered observables
            # or the inputs directly and save the value, set it as the new observable value
            new_value = o.f((get_registered_value(input) for input in o.inputs)...)
            o[] = new_value
        end
    end
    obs
end


function Base.setindex!(obs::Observable, value)
    if !obs.onlynew || obs.val != value
        obs[!] = value
    end
end

Base.getindex(obs::Observable) = obs.val

function register!(with::Observable, o::Observable)
    if o in with.listeners
        error("Observable already registered as observer.")
    end
    push!(with.listeners, o)
end


wrap_register(any) = any
wrap_register(o::Observable) = RegisteredObservable(o)

unwrap_register(any) = any
unwrap_register(ro::RegisteredObservable) = ro.o



# creating an observable from inputs and a function acting on those inputs

function observe!(f, inputs...; onlynew = false, type::Union{Type, Nothing, NoValue} = nothing)

    for i in eachindex(inputs)
        if inputs[i] isa Observable{NoValue}
            error("Input $i is an Observable{NoValue}. You can't observe such an observable as it has no value.")
        end
    end


    # compute first value if observable doesn't have the NoValue type
    # the NoValue type is for on/onany which don't store values, just execute functions
    value = if type isa NoValue
        NoValue()
    else
        f((to_value(input) for input in inputs)...)
    end


    # make a new observer that tracks who he observes but isn't yet registered with the other listeners
    param = if isnothing(type)
        # the parameter type is decided by the value
        typeof(value)
    elseif type isa NoValue
        NoValue
    else
        # the parameter type is manually given
        type
    end

    obs = Observable{param}(
        value,
        f,
        Any[wrap_register(i) for i in inputs],
        Observable[],
        onlynew)

    # register the new observable with the inputs
    for o in inputs
        if o isa Observable
            register!(o, obs)
        end
    end

    obs
end

# these functions mimick the current observables api
# the difference is that they return an observable{NoValue} and not a function
# that is because a function doesn't know about observables that keep track of it
# so it becomes more difficult to unlink

function on(f, input)
    observe!(f, input, type = NoValue())
end

# here the order is different, the listener is removed from the input
# because only that direction is possible in Observables.jl
function off(input, listener)
    stop_observing!(listener, input)
end

function onany(f, inputs...)
    observe!(f, inputs...; type = NoValue())
end





"""
    stop_observing!(observer::Observable, input::Observable)

Replace the `input` `Observable` in the input vector of the `observer` with its value
and remove the `observer` from the `listeners` of the `input` `Observable`.
"""
function stop_observing!(observer::Observable, input::Observable)
    # delete input in observer
    inputindex = findfirst(==(RegisteredObservable(input)), observer.inputs)

    if isnothing(inputindex)
        error("The input observable was not found as an input in the listener observable.")
    end

    observerindex = findfirst(==(observer), input.listeners)
    if isnothing(observerindex)
        error("The listener observable was not found as a listener in the input observable.")
    end

    observer.inputs[inputindex] = to_value(input)
    deleteat!(input.listeners, observerindex)
end


# if the input is not an observable
function stop_observing!(observer::Observable, input)
    # do nothing
end


"""
    stop_observing!(observer::Observable)
    
Replace all `Observable`s in the input vector of the `observer` with their values
and remove the `observer` from the `listeners` of each of these `Observable`s.
"""
function stop_observing!(observer::Observable)
    for input in observer.inputs
        stop_observing!(observer, unwrap_register(input))
    end
end


"""
    disable!(o::Observable; recursive = true)

Make an observable `o` stop observing all its inputs.
Set the stored function to `nothing`, so objects referenced in the
closure can possibly be released.

Then also make all listeners of `o` stop observing it.
If `recursive` is `true`, all listeners that don't have any `Observable` inputs
left after stopping are also disabled.

Returns the number of all disabled `Observable`s.
"""
function disable!(o::Observable; recursive = true)

    stop_observing!(o)
    o.f = nothing
        
    n_disabled = 1
    for observer in o.listeners
        stop_observing!(observer, o)
        # if the observer doesn't have any inputs left that are observables
        # we can disable it as well, because it will never be triggered again
        if recursive && n_observable_inputs(observer) == 0
            n_disabled += disable!(observer; recursive = true)
        end
    end
    n_disabled
end

"""
    is_disabled(o::Observable)

Checks that `o` has no observable inputs and no listeners.
Also, it should have no stored function.
"""
function is_disabled(o::Observable)
    n_observable_inputs(o) == 0 && isempty(listeners(o)) && isnothing(o.f)
end



n_ordinary_inputs(o::Observable) = sum((!isa).(o.inputs, RegisteredObservable))
n_observable_inputs(o::Observable) = sum(isa.(o.inputs, RegisteredObservable))



function Base.show(io::IO, o::Observable{V}) where V

    n_observable = n_observable_inputs(o)
    n_ordinary = n_ordinary_inputs(o)
    n_listeners = length(o.listeners)

    str = "Observable{$V} with $n_observable observable, $n_ordinary ordinary inputs, and $n_listeners listeners."
    println(io, str)
    print(io, "Value: $(o.val)")
    nothing
end



end # module
