# See also Copernicus or CHELSA for climate:
# https://cds.climate.copernicus.eu/cdsapp#!/search?type=dataset
# https://cds.climate.copernicus.eu/cdsapp#!/dataset/reanalysis-era5-land?tab=overview
# https://os.zhdk.cloud.switch.ch/envicloud/chelsa/chelsa_V2/EUR11/documentation/CHELSA_EUR11_technical_documentation.pdf


function get_data!(settings,mask)
    input_rasters = Dict{Any,Any}()
    input_rasters = merge(input_rasters,get_dtm(settings,mask))
    input_rasters = merge(input_rasters,get_soil_data(settings,mask))
    settings["res"]["fr"]["input_rasters"] = input_rasters 
end

# ------------------------------------------------------------------------------
# Specific download functions
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
    if ( isfile(tif_destpath) && (!force))
        return dtm_var
    end
    verbose && @info "Downloading dtm file..."
    Downloads.download(url,zip_destpath, verbose=verbose)
    RFR.unzip(zip_destpath,data_path)
    sr            = settings["simulation_region"]
    crs           = convert(Rasters.WellKnownText, Rasters.EPSG(sr["cres_epsg_id"]))
    lon, lat      = Rasters.X(sr["x_lb"]:(sr["xres"]/4):sr["x_ub"]), Rasters.Y(sr["y_lb"]:(rs["yres"]/4):sr["y_ub"])
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
    #rm(tif_destpath_reg)
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


function get_ecoregions_data(data_path;force=false,verbose=false,to=nothing)
    # landing page: https://www.eea.europa.eu/en/datahub/datahubitem-view/c8c4144a-8c0e-4686-9422-80dbf86bc0cb?activeAccordion=
    #force   = false
    #verbose = true
    #to      = nothing
    #to      = Yraster

    subpath     = joinpath(data_path,"ecoregions")
    classes     = collect([1:9;11:13]) # classes 10, 14 and 15 are out of the study area
    urlname     = "https://sdi.eea.europa.eu/datashare/s/sTnNeQK69iYNgCe/download"
    dataname    = "eea_r_3035_1_km_env-zones_p_2018_v01_r00"
    zippath     = joinpath(subpath,"$(dataname).zip")
    zipfolder   = joinpath(subpath,dataname)
    tifname     = joinpath(zipfolder,"$(dataname).tif")
    tifname_1km = joinpath(zipfolder,"ecoregions_1km.tif")
    tifname_8km = joinpath(zipfolder,"ecoregions_8km.tif")
    (ispath(zipfolder) && !force ) && return Dict("ecoregions" => tifname_8km)  #expand_classes(tifname_1km,classes;verbosity=verbose,force=false,to=to)

    Downloads.download(urlname,zippath, verbose=verbose)
    rm(zipfolder, force=true,recursive=true)
    unzip(zippath,subpath) # the zip archive contain itself the folder with the data inside
    rm(zippath)

    # before the extraction of the classes we get the base raster res from 100m to 1km 
    base_raster = Raster(tifname)
    base_raster_1km = resample(base_raster, res=1000)
    base_raster_8km = resample(base_raster_1km, to=to, method=:mode)
    write(tifname_8km, base_raster_8km, force=true)
    return Dict("ecoregions" => tifname_8km)

    #=
    #base_raster_1km_Float32 = Float32.(base_raster_1km)
    # replacing 0 as missing value to 99, as we need 0 as a value !
    missval       = missingval(base_raster_1km) 
    base_raster_1km = map(x-> ( (x == missval) ? UInt8(99) : x), base_raster_1km)
    base_raster_1km = rebuild(base_raster_1km; missingval=UInt8(99))
    write(tifname_1km, base_raster_1km, force=true)

    ecoregions_classes = expand_classes(tifname_1km,classes;verbosity=2,force=force,to=to)

    return ecoregions_classes
    =#
end