"""
    GenFSM_resources_init_fr

Initializer for the France side of the resource module

"""
module GenFSM_resources_init_fr

export data_path

#using Statistics, Random, Downloads # Standard Library (shipped with Julia)
#using FTPClient
#using DataFrames, CSV, Plots, DataDeps, ZipFile, DataStructures, JLD2, Pipe
#using GeoFormatTypes, ArchGDAL, Rasters, RasterDataSources
#using BetaML
#import DecisionTree
#plotlyjs()
#gr() 
#pythonplot()
#Random.seed!(123) # fix random seed

#(X,Y) = 1,2 # Workaround for Rasters.jl bug https://github.com/rafaqz/DimensionalData.jl/issues/493
# Note that the first dimension is X (the cols!) and second is Y (the row!), i.e. opposite of matrix ordering!

#data_path   = joinpath(@__DIR__,"data")
ENV["RASTERDATASOURCES_PATH"] = data_path
#include("getdata.jl")



end # module GenFSM_resources_init_fr
