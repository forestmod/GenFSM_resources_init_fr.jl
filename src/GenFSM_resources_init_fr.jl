"""
    GenFSM_resources_init_fr

Initializer for the France side of the resource module

"""
module GenFSM_resources_init_fr

export data_path, init!

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
#ENV["RASTERDATASOURCES_PATH"] = data_path
#include("getdata.jl")

function init!(pixels,mask,settings)
    println("hello w")
    #temp_ rel_temp_output
    temp_path = joinpath(settings["temp_path"],"res","fr")
    cache_path = joinpath(settings["cache_path"],"res","fr")
    output_path = joinpath(settings["output_path"],"res","fr")
    settings["res"]["fr"]["temp_path"] = temp_path
    settings["res"]["fr"]["cache_path"] = cache_path
    settings["res"]["fr"]["output_path"] = output_path
    isdir(temp_path) || mkpath(temp_path)
    isdir(cache_path) || mkpath(temp_path)
    isdir(output_path) || mkpath(output_path)
    # Download the data:
    #- administrative for the region
    #- soil 
    #- altimetry DTM
    #- corine land cover
    #- IGN
end



end # module GenFSM_resources_init_fr
