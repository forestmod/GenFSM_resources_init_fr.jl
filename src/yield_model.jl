cd(@__DIR__)
using Pkg
Pkg.activate(".")
# Pkg.add(["Plots", "DataFrames", "DataDeps", "ArchGDAL", "Rasters", "RasterDataSources","BetaML"])
# Pkg.instantiate()
using Statistics, Random, Downloads # Standard Library (shipped with Julia)
using FTPClient
using DataFrames, CSV, Plots, DataDeps, ZipFile, DataStructures, JLD2, Pipe
using GeoFormatTypes, ArchGDAL, Rasters, RasterDataSources
using BetaML
#import DecisionTree
#plotlyjs()
#gr() 
#pythonplot()
Random.seed!(123) # fix random seed

(X,Y) = 1,2 # Workaround for Rasters.jl bug https://github.com/rafaqz/DimensionalData.jl/issues/493
# Note that the first dimension is X (the cols!) and second is Y (the row!), i.e. opposite of matrix ordering!

data_path   = joinpath(@__DIR__,"data")
ENV["RASTERDATASOURCES_PATH"] = data_path
include("getdata.jl")

# We first get our Y raster as everything will be set based on it..
Yfilename = joinpath(data_path,"vol.tif")
ispath(Yfilename) || Downloads.download("ftp://anonymous@palantir.boku.ac.at//Public/ImprovedForestCharacteristics/Volume/vol.tif",Yfilename)
Yraster   = Raster(Yfilename) |> replace_missing
(nC,nR)  = size(Yraster)


# European coordinates
# - geographical
long_lb, long_ub = -12, 35
lat_lb, lat_ub   =  33, 72
eu_bounds_geo = Rasters.X(long_lb .. long_ub), Rasters.Y(lat_lb .. lat_ub)
# - projected
crs = "EPSG:3035" # projectd units are meters
X_lb, X_ub = dims(Yraster)[1][1]-8000,dims(Yraster)[1][end]+80000 # 8km margin
Y_lb, Y_ub = dims(Yraster)[2][1]-8000,dims(Yraster)[2][end]+80000 # 8km margin 
eu_bounds_proj = Rasters.X(X_lb .. X_ub), Rasters.Y(Y_lb .. Y_ub)

# use these as: myraster_eu = myraster_w[eu_bounds_geo...]

# Get the codes from the links in the download page after having filled the form for chemical, physical and other data in the forms below:
# https://esdac.jrc.ec.europa.eu/content/topsoil-physical-properties-europe-based-lucas-topsoil-data
# https://esdac.jrc.ec.europa.eu/content/chemical-properties-european-scale-based-lucas-topsoil-data 
# https://esdac.jrc.ec.europa.eu/content/european-soil-database-derived-data
soil_codes     = ["wyz_856","60","wyz_856"]
soil_ph_vars   = ["Clay","Silt","Sand","CoarseFragments","BulkDensity","TextureUSDA","AWC"]
soil_ph_vars2  = ["Clay","Silt1","Sand1","Coarse_fragments","Bulk_density","textureUSDA","AWC"] # some vars have slighly different name in the zipped file, argh!
soil_chem_vars  = ["pH_H2O","pH_CaCl","CEC","Caco3","CN","N","P","K","pH_H2O_ratio_Cacl"]
soil_chem_vars2 = ["pH_H2O","pH_CaCl","CEC","CaCO3","CN","N","P","K","pH_H2O_CaCl"] # some vars have slighly different name in the zipped file, argh!
soil_oth_vars  = [
  #"STU_EU_ALLOCATE",
  "STU_EU_DEPTH_ROOTS", "STU_EU_T_CLAY", "STU_EU_S_CLAY", "STU_EU_T_SAND",
  "STU_EU_S_SAND", "STU_EU_T_SILT", "STU_EU_S_SILT", "STU_EU_T_OC",
  "STU_EU_S_OC", "STU_EU_T_BD", "STU_EU_S_BD", "STU_EU_T_GRAVEL",
  "STU_EU_S_GRAVEL", "SMU_EU_T_TAWC", "SMU_EU_S_TAWC", "STU_EU_T_TAWC",
  "STU_EU_S_TAWC"]


# ------------------------------------------------------------------------------
# Downloading (if needed) and resampling to Y (if needed)

# The objective of this task is to have the data saved on disk and be ready for
# the analysis at the geo resolution of Y.
# Analysis can also be done on a case-by-case manner. The result is always a file.
# Normally a "force" parameter will dictate if redownload/reanalysis is required
# ---------

# Forest structure data
forest_struct_vars = get_improved_forest_structure_data(data_path,force=false) # only download, no analysis needed

# ---------
# dtm
dtm_vars = get_dtm(data_path,force=false, to=Yraster) # resample

# ---------
# npm
npp_vars = get_past_npp(data_path;force=false,to=Yraster)

# ---------
# soil
soil_vars = get_soil_data(data_path,soil_codes,soil_ph_vars,soil_ph_vars2,soil_chem_vars,soil_chem_vars2,soil_oth_vars,force=false,to=Yraster)


# ---------
# ecoregions
# This data will not be used for training as in our tests  it doesn't improve predictions (we used the classes) and it may change with cc if we want to model cc 
ecoregions_vars = get_ecoregions_data(data_path,force=false,to=Yraster)
ecoregions = Raster(ecoregions_vars["ecoregions"])

Xmeta = OrderedDict(forest_struct_vars...,soil_vars...,dtm_vars...,npp_vars...,) # var name => file path




# ------------------------------------------------------------------------------
# Loading transformed data


Xnames   = collect(keys(Xmeta))
nXnames  = length(Xnames)
Xrasters = OrderedDict{String,Raster}([i => Raster(Xmeta[i]) |> replace_missing for i in Xnames])

X   = DataFrame([Symbol(Xnames[i]) => Float64[] for i in 1:length(Xnames)])
X.R = Int64[]
X.C = Int64[]
Y   = Float64[]
ecoregion = Union{Int64,Missing}[]

allowmissing!(X) 

# Reformatting the data in a large matrix (records [pixels] x variables)
for r in 1:nR
    for c in 1:nC
       ismissing(Yraster[c,r]) && continue
       row = Dict([Xnames[i] => Xrasters[Xnames[i]][c,r] for i in 1:nXnames])
       row["R"] = r
       row["C"] = c
       push!(X,row)
       push!(Y,Yraster[c,r])
       push!(ecoregion,ecoregions[c,r])
    end
end

# ------------------------------------------------------------------------------
# Separating sdi and stemn for 2 steps predictions



# ------------------------------------------------------------------------------
# Imputing missing data...
includet("crunchdata.jl")

#XY = hcat(X,Y)
#XYfull = dropmissing(XY)
#X_full= XYfull[:,1:end-1]
#Y = XYfull[:,end]
X_full = impute_X(data_path,X,force=false)
nXnames  = length(names(X_full))
ecoregion_full = Int64.(fit!(RFImputer(forced_categorical_cols=[nXnames+1]),hcat(Matrix(X_full),ecoregion))[:,nXnames+1])

fields_not_to_scale = [(f,i) for (i,f) in enumerate(names(X_full)) if mean(X_full[!,f]) > 0.001 && mean(X_full[!,f]) < 10]

fields_not_to_scale_names, fields_not_to_scale_idx = getindex.(fields_not_to_scale,1) , getindex.(fields_not_to_scale,2)
scalermodel = Scaler(skip=fields_not_to_scale_idx)
fit!(scalermodel,Matrix(X_full))

# ------------------------------------------------------------------------------
# Running the ML model....

# Split the data in training/testing sets
((xtrain,xval,xtest),(ytrain,yval,ytest)) = partition([Matrix(X_full),Y],[0.6,0.2,0.2])
(ntrain, nval,ntest) = size.([xtrain,xval,xtest],1)
nD = size(X_full,2)
x_s      = predict(scalermodel,Matrix(X_full))
xtrain_s = predict(scalermodel,Matrix(xtrain)) # xtrain scaled
xval_s  = predict(scalermodel,Matrix(xtest)) # xtest scaled
xtest_s  = predict(scalermodel,Matrix(xtest)) # xtest scaled


nnm = get_nn_trained_model(xtrain,ytrain,xval,yval;force=false,model_file="models.jld",maxepochs=50,scmodel =scalermodel)

plot(info(nnm)["loss_per_epoch"][1:end],title="Loss per epoch", label=nothing)


# Obtain predictions and test them against the ground true observations

ŷtrain         = predict(nnm,xtrain_s) 
ŷtest          = predict(nnm,xtest_s ) 

rme_train      = relative_mean_error(ytrain,ŷtrain)  # 0.1517 # 0.1384 # 0.165
rme_test       = relative_mean_error(ytest,ŷtest) # 0.1613 # 0.1766 # 0.183

# Plotting observed vs estimated...
scatter(ytrain,ŷtrain,xlabel="vols (obs)",ylabel="vols (est)",label=nothing,title="Est vs. obs in training period",xrange=[0,1000],yrange=[0,1000])
scatter(ytest,ŷtest,xlabel="vols (obs)",ylabel="vols (est)",label=nothing,title="Est vs. obs in testing period",xrange=[0,1000],yrange=[0,1000])

# ------------------------------------------------------------------------------
# Creating a raster with the estimated values

Y_est   = @pipe X_full |> Matrix |> predict(scalermodel,_) |> predict(nnm,_)
vol_est = deepcopy(Yraster)

for i in 1:length(Y_est)
    r = convert(Int64,X_full[i,"R"])
    c = Int64(X_full[i,"C"])
   # println("$r , $c : $(vol_est[c,r]) (true) \t $(Y_est[i]) (est)")
    vol_est[c,r] = Y_est[i] #missing #Y_est[i]
end

plot(Yraster,title="Actual volumes")
plot(vol_est,title="Model estimated volumes (NN model)")

# Only relative to test pixels

vol_true = deepcopy(Yraster)
vol_est  = deepcopy(Yraster)

# initialisation with missing data
[vol_true[c,r] = missing for r in 1:nR, c in 1:nC]
[vol_est[c,r] = missing for r in 1:nR, c in 1:nC]


for i in 1:length(ŷtest)
    r = convert(Int64,xtest[i,end-1])
    c = Int64(xtest[i,end])
    vol_true[c,r] = ytest[i]
    vol_est[c,r] = ŷtest[i]
end

plot(vol_true,title="Actual volumes (test pixels)")
plot(vol_est,title="Model estimated volumes (test pixels NN model)")


# ------------------------------------------------------------------------------
# Using Random Forest model

rfm = get_rf_trained_model(xtrain_s,ytrain;force=false,model_file="models.jld")
ŷtrain     = predict(rfm, predict(scalermodel,xtrain)) 
ŷtest      = predict(rfm, predict(scalermodel,xtest)) 

rme_train  = relative_mean_error(ytrain,ŷtrain) # 0.109 0.109 0.077
rme_test   = relative_mean_error(ytest,ŷtest) # 0.193 0.2114 0.2226

# Plotting observed vs estimated...
scatter(ytrain,ŷtrain,xlabel="vols (obs)",ylabel="vols (est)",label=nothing,title="Est vs. obs in training period")
scatter(ytest,ŷtest,xlabel="vols (obs)",ylabel="vols (est)",label=nothing,title="Est vs. obs in testing period")

Y_est   = @pipe X_full |> Matrix |> predict(scalermodel,_) |> predict(rfm,_)
vol_est = deepcopy(Yraster)

for i in 1:length(Y_est)
    r = X[i,"R"]
    c = X[i,"C"]
   # println("$r , $c : $(vol_est[r,c]) (true) \t $(Y_est[i]) (est)")
    vol_est[c,r] = Y_est[i]
end

plot(Yraster,title="Actual volumes")
plot(vol_est,title="Model estimated volumes (rf)")

# ------------------------------------------------------------------------------
# Manual test with a single class
Xm = copy(X_full)

Xm.agecl1 .= 1.0
Xm.agecl2 .= 0.0
Xm.agecl3 .= 0.0
Xm.agecl4 .= 0.0
Xm.agecl5 .= 0.0
Xm.agecl6 .= 0.0
Xm.agecl7 .= 0.0
Xm.agecl8 .= 0.0

Ya1   = @pipe Xm |> Matrix |> predict(scalermodel,_) |> predict(nnm,_)
vol_est = deepcopy(Yraster)
for i in 1:length(Y_est)
    r = X[i,"R"]
    c = X[i,"C"]
   # println("$r , $c : $(vol_est[r,c]) (true) \t $(Y_est[i]) (est)")
    vol_est[c,r] = Ya1[i]
end

plot(Yraster,title="Actual volumes")
plot(vol_est,title="Model estimated volumes age cl 1")

## 

estvol = get_estvol(x_s,nnm,8,8;force=true,data_file="estvol.csv")

estvol_byreg = DataFrames.combine(groupby(estvol,["ecoreg","spgr","agegr"]),  "estvol" => median => "estvol", nrow)

estvol_byreg[estvol_byreg.ecoreg .== 1 .&& estvol_byreg.spgr .== 2 ,:]

for spgr in 1:8
    for er in 0:13
        if er == 0
            plot(estvol_byreg[estvol_byreg.ecoreg .== er .&& estvol_byreg.spgr .== spgr ,"estvol"], labels="er $er", title="Fitted volumes spgr $spgr")
        elseif er < 13
            plot!(estvol_byreg[estvol_byreg.ecoreg .== er .&& estvol_byreg.spgr .== spgr ,"estvol"], labels="er $er", title="Fitted volumes spgr $spgr")
        else
            display(plot!(estvol_byreg[estvol_byreg.ecoreg .== er .&& estvol_byreg.spgr .== spgr ,"estvol"], labels="er $er", title="Fitted volumes spgr $spgr"))
        end
    end
end