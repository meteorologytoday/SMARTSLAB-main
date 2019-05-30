using Distributed

@everywhere module MLMML

    using Printf
    using Formatting
    using SharedArrays
    using Distributed
    using SparseArrays
    using NCDatasets

    macro hinclude(path)
        return :(include(joinpath(@__DIR__, $path)))
    end
        
    @hinclude("../share/constants.jl")
    @hinclude("OceanColumnCollection.jl")
    @hinclude("trivial_functions.jl")
    @hinclude("stepOceanColumnCollection.jl")
    @hinclude("takeSnapshot.jl")
end
