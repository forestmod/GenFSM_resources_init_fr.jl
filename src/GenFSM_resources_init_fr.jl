"""
    GenFSM_resources_init_fr

Initializer for the France side of the resource module

"""
module GenFSM_resources_init_fr

import Downloads 
import ArchGDAL, Rasters, ZipFile, DataStructures # , FTPClient
import Geomorphometry # for slope and aspect 
import Shapefile
import CSV, DataFrames
import Proj # to convert the (X,Y) coordinates of the inventory points

#using FTPClient, ZipFile, DataStructures #, RasterDataSources

export data_path, init!!

include("Utils.jl")

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

#ENV["RASTERDATASOURCES_PATH"] = "/home/lobianco/CloudFiles/beta-lorraine-sync/MrFOR/dev_GenFSM/cache/res/fr"

include("Get_data.jl")

function init!!(pixels,settings,overal_region_mask)
    temp_path = joinpath(settings["temp_path"],"res","fr")
    cache_path = joinpath(settings["cache_path"],"res","fr")
    output_path = joinpath(settings["output_path"],"res","fr")
    settings["res"]["fr"]["temp_path"] = temp_path
    settings["res"]["fr"]["cache_path"] = cache_path
    settings["res"]["fr"]["output_path"] = output_path
    isdir(temp_path) || mkpath(temp_path)
    isdir(cache_path) || mkpath(temp_path)
    isdir(output_path) || mkpath(output_path)
    settings["res"]["fr"]["mask"] = get_mask(settings,overal_region_mask)
    mask = Rasters.Raster(settings["res"]["fr"]["mask"])

    get_data!(settings,mask)
    println(settings)
    
    # Download the data:
    #- DONE administrative for the region
    #- DONE soil 
    #- DONE altimetry DTM
    #- Corine land cover
    #- IGN
    #- Climate

end








end # module GenFSM_resources_init_fr
