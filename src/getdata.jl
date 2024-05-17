# See also Copernicus or CHELSA for climate:
# https://cds.climate.copernicus.eu/cdsapp#!/search?type=dataset
# https://cds.climate.copernicus.eu/cdsapp#!/dataset/reanalysis-era5-land?tab=overview
# https://os.zhdk.cloud.switch.ch/envicloud/chelsa/chelsa_V2/EUR11/documentation/CHELSA_EUR11_technical_documentation.pdf

# ------------------------------------------------------------------------------
# Utility functions....

"""
    unzip(file,exdir=“”)

Unzip a zipped archive using ZipFile

# Arguments
- `file`: a zip archive to unzip and extract (absolure or relative path)
- `exdir=""`: an optional directory to specify the root of the folder where to extract the archive (absolute or relative).

# Notes
- The function doesn’t perform a check to see if all the zipped files have a common root.

# Examples

```julia
julia> unzip("myarchive.zip","myoutputdata")
```
"""
function unzip(file,exdir="")
    fileFullPath = isabspath(file) ?  file : joinpath(pwd(),file)
    basePath = dirname(fileFullPath)
    outPath = (exdir == "" ? basePath : (isabspath(exdir) ? exdir : joinpath(pwd(),exdir)))
    isdir(outPath) ? "" : mkdir(outPath)
    zarchive = ZipFile.Reader(fileFullPath)
    for f in zarchive.files
        fullFilePath = joinpath(outPath,f.name)
        if (endswith(f.name,"/") || endswith(f.name,"\\"))
            mkdir(fullFilePath)
        else
            write(fullFilePath, read(f))
        end
    end
    close(zarchive)
end

# Modified to get the info if it is a directory and to list info on any directories, not only current one
function FTP_readdir(ftp::FTP,dir=pwd(ftp);details=false)
    resp = nothing
    try
        resp = FTPClient.ftp_command(ftp.ctxt, "LIST $dir")
    catch err
        if isa(err, FTPClient.FTPClientError)
            err.msg = "Failed to list directories."
        end
        rethrow()
    end
    dir     = split(read(resp.body, String), '\n')
    dir     = filter(x -> !isempty(x), dir)
    
    if(details)
        entries = NamedTuple{(:type, :permissions, :n, :user, :group, :size, :date, :name), Tuple{Char, SubString{String}, SubString{String}, SubString{String}, SubString{String}, SubString{String}, SubString{String}, String}}[]
        for item in dir
            details = split(item)
            details_nt = (type=details[1][1],permissions=details[1][2:end],n=details[2],user=details[3],group=details[4],size=details[5],date=join(details[6:8], ' '),name=join(details[9:end], ' '))
            push!(entries,details_nt)
        end
        return entries
    else
        names = [join(split(line)[9:end], ' ') for line in dir]
        return names
    end
end

function download_dir(ftp,dir="";as="",verbosity=0, recursive=true, force=false, dryrun=false, mode=binary_mode, exclude=[], ftp_basepath="",dest_basepath="" ) # latest two used for recursion only
    (dir == "")  && (dir = pwd(ftp))
    if as == ""
        if endswith(dir,'/')
            as = split(dir,'/')[end-1]
        else
            as = split(dir,'/')[end]
        end
    end
    if ftp_basepath == ""
        if startswith(dir,"/")
            ftp_basepath = dir
        else
            ftp_basepath = joinpath(pwd(ftp),dir)
        end
    end
    (dest_basepath == "") && (dest_basepath = as)
    verbosity > 0       && println("Processing ftp directory `$(ftp_basepath)`:")
    items = FTP_readdir(ftp,dir;details=true)
    if !isempty(items)
        if !ispath(dest_basepath)
            mkdir(dest_basepath)
        elseif force
            rm(dest_basepath,recursive=true)
            mkdir(dest_basepath)
        else
            error("`$(dest_basepath)` exists on local system. Use `force=true` to override.")
        end
    end
    for item in items
        ftpname  = joinpath(ftp_basepath,item.name)
        destname = joinpath(dest_basepath,item.name)
        if(item.type != 'd')
            ftpname in exclude && continue
            verbosity > 1 &&  print(" - downloading ftp file `$(ftpname)` as local file `$(destname)`...")
            if ispath(destname)
                if force
                    rm(destname)
                else
                    error("`$(destname)` exists on local system. Use `force=true` to override.")
                end
            end      
            dryrun ? write(destname,ftpname)  : FTPClient.download(ftp, ftpname, destname, mode=mode)
            verbosity > 1 && println(" done!")
        elseif recursive
            newdir = joinpath(ftp_basepath,item.name)
            download_dir(ftp,newdir;as=destname,ftp_basepath=newdir,dest_basepath=destname, verbosity=verbosity, recursive=recursive, force=force, mode=mode, dryrun=dryrun, exclude=exclude)
        end
    end
end

function expand_classes(input_filename,classes;verbosity=2,force=false,to=nothing,writefile=true)
    out_dir   = joinpath(dirname(input_filename),"classes")
    base_name = splitext(basename(input_filename))[1]
    class_vars = OrderedDict(["$(base_name)_cl_$(cl)" => joinpath(out_dir,"$(base_name)_cl_$(cl).tif") for cl in classes])
    (ispath(out_dir) && !force ) && return class_vars
    rm(out_dir,recursive=true,force=true)
    mkdir(out_dir)
    base_raster   = Raster(input_filename) #|> replace_missing
    class_rasters = Dict{String,Raster}()
    (nC,nR)       = size(base_raster)
    missval       = missingval(base_raster) 
    missval_float = Float32(missval)
    for cl in classes
        (verbosity>1) && println("Processing class $cl ...")
        class_rasters["cl_$(cl)"] = map(x-> ( (x == missval) ? missval_float : (x == cl ? 1.0f0 : 0.0f0 ) ), base_raster)
        outfile = joinpath(out_dir,"$(base_name)_cl_$(cl).tif")
        if !isnothing(to)
            class_rasters["cl_$(cl)"] = resample(class_rasters["cl_$(cl)"],to=to,method=:average)
        end
        writefile && write(outfile, class_rasters["cl_$(cl)"] )
    end
    return class_vars
end

# ------------------------------------------------------------------------------
# Specific download functions

function get_improved_forest_structure_data(data_path;force=false)
    # Associated paper: https://doi.org/10.3390/rs14020395
    # Alternative manual data download:  wget -r -nH --cut-dirs=2 -nc ftp://anonymous@palantir.boku.ac.at//Public/ImprovedForestCharacteristics
    dest_dir = joinpath(data_path,"ImprovedForestCharacteristics")
    forest_struct_vars = OrderedDict(
        "agecl1" => joinpath(dest_dir,"Age","agecl_1_perc.tif"),
        "agecl2" => joinpath(dest_dir,"Age","agecl_2_perc.tif"),
        "agecl3" => joinpath(dest_dir,"Age","agecl_3_perc.tif"),
        "agecl4" => joinpath(dest_dir,"Age","agecl_4_perc.tif"),
        "agecl5" => joinpath(dest_dir,"Age","agecl_5_perc.tif"),
        "agecl6" => joinpath(dest_dir,"Age","agecl_6_perc.tif"),
        "agecl7" => joinpath(dest_dir,"Age","agecl_7_perc.tif"),
        "agecl8" => joinpath(dest_dir,"Age","agecl_8_perc.tif"),
        #"sdi"    => joinpath(dest_dir,"Stand_Density_Index", "sdi.tif"),
        #"stemn"  => joinpath(dest_dir,"Stem_Number", "nha.tif"),
        "spgr1"  => joinpath(dest_dir,"Tree_Species_Group","tsg_1_perc.tif"),
        "spgr2"  => joinpath(dest_dir,"Tree_Species_Group","tsg_2_perc.tif"),
        "spgr3"  => joinpath(dest_dir,"Tree_Species_Group","tsg_3_perc.tif"),
        "spgr4"  => joinpath(dest_dir,"Tree_Species_Group","tsg_4_perc.tif"),
        "spgr5"  => joinpath(dest_dir,"Tree_Species_Group","tsg_5_perc.tif"),
        "spgr6"  => joinpath(dest_dir,"Tree_Species_Group","tsg_6_perc.tif"),
        "spgr7"  => joinpath(dest_dir,"Tree_Species_Group","tsg_7_perc.tif"),
        "spgr8"  => joinpath(dest_dir,"Tree_Species_Group","tsg_8_perc.tif"),
    )
    if isdir(dest_dir) && !force
        return forest_struct_vars
    end
    ftp_init();
    ftp = FTP(hostname = "palantir.boku.ac.at", username = "anonymous", password = "")
    download_dir(ftp,"/Public/ImprovedForestCharacteristics",as=dest_dir,verbosity=2,force=force)
    return forest_struct_vars
end

function get_dtm(data_path;force=false,to=nothing)
    dtm_filename = joinpath(data_path,"WorldClim","Elevation","dtm_1Km_eu.tif")
    dtm_vars = OrderedDict("dtm"=>dtm_filename)
    if ispath(joinpath(data_path,"WorldClim","Elevation")) && !force
        return dtm_vars 
    end
    if(force)
        rm(joinpath(data_path,"WorldClim","Elevation"), recursive=true, force=true)
    end
    dtm_w_filename = getraster(WorldClim{Elevation}, :elev; res="30s")

    if !isnothing(to)
        dtm_w  = Raster(dtm_w_filename)
        dtm_eu = resample(dtm_w,to=Yraster,method=:average)
        write(dtm_filename, dtm_eu)
    else
        mv(dtm_w_filename,dtm_filename)
    end
    return dtm_vars
end


function get_past_npp(data_path;force=false,to=nothing)
    # Associated paper: https://doi.org/doi:10.3390/rs8070554
    dest_dir     = joinpath(data_path,"MODIS_EURO")
    npp_filename = joinpath(data_path,"MODIS_EURO","npp_mean_eu_8km.tif")
    npp_vars = OrderedDict("npp" => npp_filename)
    npp_hd_filename = joinpath(data_path,"MODIS_EURO","EU_NPP_mean_2000_2012.tif")
    if isdir(dest_dir) && !force
        return npp_vars
    end
    ftp_init();
    ftp = FTP(hostname = "palantir.boku.ac.at", username = "anonymous", password = "")
    download_dir(ftp,"/Public/MODIS_EURO",as=dest_dir,verbosity=2,force=force,exclude=["/Public/MODIS_EURO/Neumann et al._2016_Creating a Regional MODIS Satellite-Driven Net Primary Production Dataset for European Forests.pdf"])
    if isnothing(to)
        cp(npp_hd_filename,npp_filename)
        return npp_vars
    else
        npp_hr = Raster(npp_hd_filename,missingval=65535.0f0)
        npp    = resample(npp_hr,to=Yraster,method=:average)
        write(npp_filename, npp, force=true)
        return npp_vars
    end
end


function download_soil_data(data_path,soil_codes,soil_ph_vars,soil_chem_vars;force=false,verbose=false)

    # Soil:
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
    soil_path = joinpath(data_path,"soil")

    for var in soil_ph_vars
        urlname   = "https://esdac.jrc.ec.europa.eu/$(soil_codes[1])/_33_GSM/$(var)_Extra.zip"
        zipname   = joinpath(soil_path,"$(var).zip")
        zipfolder = joinpath(soil_path,var)
        #tifname   = joinpath(soil_path,var,"$(var).tif")
        (ispath(zipfolder) && !force ) && continue
        Downloads.download(urlname,zipname, verbose=verbose)
        unzip(zipname,zipfolder)
        rm(zipname)
    end

    for var in soil_chem_vars
        urlname   = "https://esdac.jrc.ec.europa.eu/public_path/shared_folder/dataset/$(soil_codes[2])/$(var).zip"
        zipname   = joinpath(soil_path,"$(var).zip")
        zipfolder = joinpath(soil_path,var)
        #tifname   = joinpath(soil_path,var,"$(var).tif")
        (ispath(zipfolder) && !force ) && continue
        Downloads.download(urlname,zipname, verbose=verbose)
        unzip(zipname,zipfolder)
        rm(zipname)
    end

    urlname   = "https://esdac.jrc.ec.europa.eu/$(soil_codes[3])/_24_DER/STU_EU_Layers.zip"
    zipname   = joinpath(soil_path,"STU_EU_Layers.zip")
    zipfolder = joinpath(soil_path,"STU_EU_Layers")

    (ispath(zipfolder) && !force ) && return nothing
    Downloads.download(urlname,zipname, verbose=verbose)
    unzip(zipname,zipfolder)
    rm(zipname)
end

function get_soil_data(data_path,soil_codes,soil_ph_vars,soil_ph_vars2,soil_chem_vars,soil_chem_vars2,soil_oth_vars;force=false,verbose=false,to=nothing)
    soil_path = joinpath(data_path,"soil")
    soil_classes = 1:12
    download_soil_data(data_path,soil_codes,soil_ph_vars,soil_chem_vars;force=force,verbose=verbose)
    texture_filename = joinpath(data_path,"soil","TextureUSDA","textureUSDA.tif")
    texture_classes = expand_classes(texture_filename,soil_classes;verbosity=2,force=force,to=to)
    soil_vars1 = vcat(soil_ph_vars,soil_chem_vars,soil_oth_vars)
    soil_vars2 = vcat(soil_ph_vars2,soil_chem_vars2,soil_oth_vars)
    soil_vars  = OrderedDict{String,String}()
    nvars_ph_chem = length(soil_ph_vars)+length(soil_chem_vars)
    for (i,var) in enumerate(soil_vars1)
        if i <= nvars_ph_chem
            if var != "TextureUSDA"
                saved_file = joinpath(soil_path,var,"$(soil_vars2[i]).tif")
                final_file = joinpath(soil_path,var,"$(soil_vars2[i])_eu.tif")
                if ispath(final_file) && !force 
                    soil_vars[var] = final_file
                    continue
                end
                if !isnothing(to)
                    orig_raster = Raster(saved_file)
                    resampled_raster = resample(orig_raster,to=to,method=:average)
                    write(final_file, resampled_raster, force=true)
                else
                    cp(saved_file, final_file)
                end
                soil_vars[var] = final_file
            else
                soil_vars = OrderedDict(soil_vars..., texture_classes...)
            end
        else
            saved_file = joinpath(soil_path,"STU_EU_Layers","$(soil_vars2[i]).rst")
            final_file = joinpath(soil_path,"STU_EU_Layers","$(soil_vars2[i])_eu.tif")
            if ispath(final_file) && !force 
                soil_vars[var] = final_file
                continue
            end
            if !isnothing(to)
                orig_raster = Raster(saved_file,crs="EPSG:3035") # ,missingval=0.0f0)  missing value is zero, but zero is used also as true value! 
                resampled_raster = resample(orig_raster,to=to,method=:average)
                write(final_file, resampled_raster, force=true)
            else
                cp(saved_file, final_file)
            end
            soil_vars[var] = final_file
        end
    end
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