# See also Copernicus or CHELSA for climate:
# https://cds.climate.copernicus.eu/cdsapp#!/search?type=dataset
# https://cds.climate.copernicus.eu/cdsapp#!/dataset/reanalysis-era5-land?tab=overview
# https://os.zhdk.cloud.switch.ch/envicloud/chelsa/chelsa_V2/EUR11/documentation/CHELSA_EUR11_technical_documentation.pdf


function get_data!(settings,mask)
    input_rasters = Dict{Any,Any}()
    input_rasters = merge(input_rasters,get_dtm(settings,mask))
    input_rasters = merge(input_rasters,get_soil_data(settings,mask))
    input_rasters = merge(input_rasters,get_clc(settings,mask))
    settings["res"]["fr"]["input_rasters"] = input_rasters
end

# ------------------------------------------------------------------------------
# Specific download functions

function get_mask(settings,mask)
    force          = "adm_borders" in settings["res"]["fr"]["force_download"]
    verbosity      = settings["verbosity"]
    verbose        = verbosity in ["HIGH", "FULL"] 
    admin_borders_input_crs = settings["res"]["fr"]["data_sources"]["admin_borders_input_crs"]

    adm_borders_path      = joinpath(settings["res"]["fr"]["cache_path"],"adm_borders")
    isdir(adm_borders_path) || mkpath(adm_borders_path)
    adm_borders_dl_path   = joinpath(adm_borders_path,"downloaded")
    isdir(adm_borders_dl_path) || mkpath(adm_borders_dl_path)

    mask_destpath         = joinpath(adm_borders_path,"mask.tif")

    (isfile(mask_destpath) && (!force)) && return mask_destpath

    for f in settings["res"]["fr"]["data_sources"]["admin_borders_sources"]
        fname     = basename(split(f,"?")[1])
        dest_name = joinpath(adm_borders_dl_path,fname)
        Downloads.download(f,dest_name, verbose=verbose)
    end
    dir_files = readdir(adm_borders_dl_path)
    shp_file = dir_files[findfirst(x->match(r".*\.shp$", x) !== nothing, dir_files)]

    reg_borders = Shapefile.Handle(joinpath(adm_borders_dl_path,shp_file)).shapes

    reg_raster = Rasters.rasterize(last, reg_borders; res=0.01, missingval=0, fill=1, progress=true)
    shp_crs           = convert(Rasters.WellKnownText, Rasters.EPSG(admin_borders_input_crs))
    reg_raster = Rasters.setcrs(reg_raster, shp_crs)
    reg_raster  = Rasters.reverse(reg_raster;dims=Rasters.Y )
    #Rasters.metadata(reg_raster)["missed_geometries"]

    resampled_raster = Rasters.resample(reg_raster,to=mask,method=:average)
    write(mask_destpath, resampled_raster ,force=true)
    rm(adm_borders_dl_path,recursive=true)
    return mask_destpath
end


"""
   get_dtm(settings,mask)

Download and resample to mask dtm and related variables (slope, aspect, 
Terrain Ruggedness Index)

"""
function get_dtm(settings,mask)
    data_path        = joinpath(settings["res"]["fr"]["cache_path"],"dtm")
    isdir(data_path) || mkpath(data_path)
    force            = "dtm" in settings["res"]["fr"]["force_download"]
    url              = settings["res"]["fr"]["data_sources"]["dtm_url"]
    to               = mask
    filename         = basename(url)
    verbosity        = settings["verbosity"]
    verbose          = verbosity in ["HIGH", "FULL"] 
    zip_destpath     = joinpath(data_path,filename)
    tif_destpath     = replace(zip_destpath,".zip" => ".tif")
    tif_destpath_reg = replace(tif_destpath,".tif" => "_reg.tif")
    slope_destpath   = joinpath(data_path,"slope.tif")
    aspect_destpath  = joinpath(data_path,"aspect.tif")
    tri_destpath     = joinpath(data_path,"tri.tif")
    dtm_var          = DataStructures.OrderedDict(
        "dtm"=>tif_destpath_reg,
        "slope"=>slope_destpath,
        "aspect"=>aspect_destpath,
        "tri"=>tri_destpath,
        )
    if ( isfile(tif_destpath_reg) && (!force))
        return dtm_var
    end
    verbose && @info "Downloading dtm file..."
    Downloads.download(url,zip_destpath, verbose=verbose)
    unzip(zip_destpath,data_path)
    sr            = settings["simulation_region"]
    crs           = convert(Rasters.WellKnownText, Rasters.EPSG(sr["cres_epsg_id"]))
    lon, lat      = Rasters.X(sr["x_lb"]:(sr["xres"]/4):sr["x_ub"]), Rasters.Y(sr["y_lb"]:(sr["yres"]/4):sr["y_ub"])
    mask_hr       = Rasters.Raster(zeros(Float32,lon,lat),crs=crs)
    mask_hr       = Rasters.reverse(mask_hr;dims=Rasters.Y )
    dtm_w         = Rasters.Raster(tif_destpath)
    dtm_reg_hr    = Rasters.resample(dtm_w,to=mask_hr,method=:average)
    dtm_reg       = Rasters.resample(dtm_w,to=to,method=:average)
    M             = convert(Matrix{Float32},dtm_reg_hr[:,:])
    slope         = Geomorphometry.slope(M)
    aspect        = Geomorphometry.aspect(M)
    tri           = Geomorphometry.TRI(M)
    slope_r       = similar(mask_hr)
    aspect_r      = similar(mask_hr)
    tri_r         = similar(mask_hr)
    slope_r[:,:]  = slope
    aspect_r[:,:] = aspect
    tri_r[:,:]    = tri
    slope_r_lr    = Rasters.resample(slope_r,to=to,method=:average)
    aspect_r_lr   = Rasters.resample(aspect_r,to=to,method=:average)
    tri_r_lr      = Rasters.resample(tri_r,to=to,method=:average)
    write(tif_destpath_reg, dtm_reg,force=true)
    write(slope_destpath, slope_r_lr,force=true)
    write(aspect_destpath, aspect_r_lr,force=true)
    write(tri_destpath, tri_r_lr,force=true)
    rm(zip_destpath)
    rm(tif_destpath)
    return dtm_var
end

function get_soil_data(settings,mask)
    #=
    All soil datasets:
    https://esdac.jrc.ec.europa.eu/resource-type/european-soil-database-soil-properties

    Soil_physical 
    https://esdac.jrc.ec.europa.eu/content/topsoil-physical-properties-europe-based-lucas-topsoil-data
    https://www.sciencedirect.com/science/article/pii/S0016706115300173

    Soil chemistry
    https://esdac.jrc.ec.europa.eu/content/chemical-properties-european-scale-based-lucas-topsoil-data
    https://www.sciencedirect.com/science/article/pii/S0016706119304768

    Soil other derived data
    https://esdac.jrc.ec.europa.eu/content/european-soil-database-derived-data
    Hiederer, R. 2013. Mapping Soil Properties for Europe - Spatial Representation of Soil Database Attributes. Luxembourg: Publications Office of the European Union - 2013 - 47pp. EUR26082EN Scientific and Technical Research series, ISSN 1831-9424, doi:10.2788/94128
    Hiederer, R. 2013. Mapping Soil Typologies - Spatial Decision Support Applied to European Soil Database. Luxembourg: Publications Office of the European Union - 2013 - 147pp. EUR25932EN Scientific and Technical Research series, ISSN 1831-9424, doi:10.2788/8728
    =#

    soil_path      = joinpath(settings["res"]["fr"]["cache_path"],"soil")
    isdir(soil_path) || mkpath(soil_path)
    soil_ph_url    = settings["res"]["fr"]["data_sources"]["soil_ph_url"]
    soil_chem_url  = settings["res"]["fr"]["data_sources"]["soil_chem_url"]
    soil_oth_url   = settings["res"]["fr"]["data_sources"]["soil_oth_url"]
    soil_ph_vars   = settings["res"]["fr"]["data_sources"]["soil_ph_vars"]
    soil_chem_vars = settings["res"]["fr"]["data_sources"]["soil_chem_vars"]
    soil_oth_vars  = settings["res"]["fr"]["data_sources"]["soil_oth_vars"]
    force          = "soil" in settings["res"]["fr"]["force_download"]
    verbosity      = settings["verbosity"]
    verbose        = verbosity in ["HIGH", "FULL"] 
    to             = mask
    soil_vars      = DataStructures.OrderedDict{String,String}()
    n_soil_ph_vars = length(soil_ph_vars)
    soil_texture_n_classes = settings["res"]["fr"]["data_sources"]["soil_texture_n_classes"]
    crs = convert(Rasters.WellKnownText, Rasters.EPSG(settings["simulation_region"]["cres_epsg_id"]))

    # Soil and chemistry variables....
    for (i,var) in enumerate(vcat(soil_ph_vars,soil_chem_vars))
        if i <= n_soil_ph_vars
            urlname   = replace(soil_ph_url,"\${VAR}" => var)
        else
            urlname   = replace(soil_chem_url,"\${VAR}" => var)
        end
        zipname   = joinpath(soil_path,"$(var).zip")
        zipfolder = joinpath(soil_path,var)
        final_file = joinpath(soil_path,"$(var)_reg.tif") 
        if (ispath(final_file) && !force )
            soil_vars[var] = final_file
            continue
        end
        Downloads.download(urlname,zipname, verbose=verbose)
        unzip(zipname,zipfolder)
        dir_files = readdir(zipfolder)
        tif_file = dir_files[findfirst(x->match(r".*\.tif$", x) !== nothing, dir_files)]
        saved_file = joinpath(zipfolder,tif_file)
        orig_raster = Rasters.Raster(saved_file)
        resampled_raster = Rasters.resample(orig_raster,to=to,method=:average)
        write(final_file, resampled_raster, force=true)
        soil_vars[var] = final_file
        rm(zipname)
        rm(zipfolder,recursive=true)
    end

    # Special: for TextureUSDA we extract the class as boolean values, as this is categorical
    soil_texture_classes = 1:soil_texture_n_classes
    texture_filename = joinpath(soil_path,"TextureUSDA_reg.tif")
    texture_classes = expand_classes(texture_filename,soil_texture_classes;verbose=verbose,force=force,to=nothing)
    delete!(soil_vars,"TextureUSDA")
    soil_vars = DataStructures.OrderedDict(soil_vars..., texture_classes...)

    # Other soil variables
    urlname   = soil_oth_url
    zipname   = joinpath(soil_path,basename(urlname))
    zipfolder = joinpath(soil_path, split(basename(urlname),".")[1])
    finalfolder = joinpath(soil_path,"soil_oth_vars")
    if (ispath(finalfolder) && (!force) )
        return soil_vars
    end
    ispath(finalfolder) || mkpath(finalfolder)
    Downloads.download(urlname,zipname, verbose=verbose)
    unzip(zipname,zipfolder)
    for var in soil_oth_vars
        saved_file = joinpath(zipfolder,"$(var).rst")
        final_file = joinpath(finalfolder,"$(var)_reg.tif")
        orig_raster = Rasters.Raster(saved_file,crs=crs) # ,missingval=0.0f0)  missing value is zero, but zero is used also as true value! 
        resampled_raster = Rasters.resample(orig_raster,to=to,method=:average)
        write(final_file, resampled_raster,force=true)
        soil_vars[var] = final_file
    end
    rm(zipname)
    rm(zipfolder,recursive=true)
    return soil_vars
end

function get_clc(settings,mask)
    clc_dirpath   = joinpath(settings["res"]["fr"]["cache_path"],"clc")
    clc_dldirpath = joinpath(settings["res"]["fr"]["temp_path"],"clc")
    clc_dlpath    = joinpath(clc_dldirpath,"clc.gpkg")
    clc_bfor_path = joinpath(clc_dirpath,"clc_bfor.tif")
    clc_cfor_path = joinpath(clc_dirpath,"clc_cfor.tif")
    clc_mfor_path = joinpath(clc_dirpath,"clc_mfor.tif")
    clc_vars = Dict(
        "clc_bfor" => clc_bfor_path,
        "clc_cfor" => clc_cfor_path,
        "clc_mfor" => clc_mfor_path,
    )
    clc_url = settings["res"]["fr"]["data_sources"]["clc_url"]
    force          = "clc" in settings["res"]["fr"]["force_download"]
    (isdir(clc_dirpath) && (!force) ) && return clc_vars
    isdir(clc_dirpath) || mkpath(clc_dirpath)
    isdir(clc_dldirpath) || mkpath(clc_dldirpath)
    Downloads.download(clc_url,clc_dlpath)
    clc_df  = GeoDataFrames.read(clc_dlpath)
    DataFrames.rename!(clc_df,"Shape" => "geometry")
    clc_bfor = clc_df[clc_df.Code_18 .== "311",:]
    clc_cfor = clc_df[clc_df.Code_18 .== "312",:]
    clc_mfor = clc_df[clc_df.Code_18 .== "313",:]
    Logging.with_logger(Logging.NullLogger()) do
        clc_bfor_share = Rasters.coverage(clc_bfor; to=mask)
        clc_cfor_share = Rasters.coverage(clc_cfor; to=mask)
        clc_mfor_share = Rasters.coverage(clc_mfor; to=mask)
        write(clc_bfor_path, clc_bfor_share ,force=true)
        write(clc_cfor_path, clc_cfor_share ,force=true)
        write(clc_mfor_path, clc_mfor_share ,force=true)
    end
    rm(clc_dldirpath, recursive=true)
    return clc_vars
end