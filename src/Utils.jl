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

#=
# Modified to get the info if it is a directory and to list info on any directories, not only current one
function FTP_readdir(ftp::FTPClient.FTP,dir=pwd(ftp);details=false)
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
    items = FTPClient.FTP_readdir(ftp,dir;details=true)
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
=#

function expand_classes(input_filename,classes;verbose=false,force=false,to=nothing,writefile=true)
    out_dir   = joinpath(dirname(input_filename),"classes")
    base_name = splitext(basename(input_filename))[1]
    class_vars = DataStructures.OrderedDict(["$(base_name)_cl_$(cl)" => joinpath(out_dir,"$(base_name)_cl_$(cl).tif") for cl in classes])
    (ispath(out_dir) && !force ) && return class_vars
    rm(out_dir,recursive=true,force=true)
    mkdir(out_dir)
    base_raster   = Rasters.Raster(input_filename) #|> replace_missing
    class_rasters = Dict{String,Rasters.Raster}()
    (nC,nR)       = size(base_raster)
    missval       = Rasters.missingval(base_raster) 
    missval_float = Float32(missval)
    for cl in classes
        verbose && println("Processing class $cl ...")
        class_rasters["cl_$(cl)"] = map(x-> ( (x == missval) ? missval_float : (x == cl ? 1.0f0 : 0.0f0 ) ), base_raster)
        outfile = joinpath(out_dir,"$(base_name)_cl_$(cl).tif")
        if !isnothing(to)
            class_rasters["cl_$(cl)"] = Rasters.resample(class_rasters["cl_$(cl)"],to=to,method=:average)
        end
        println(outfile)
        #class_rasters["cl_$(cl)"][:,:] = class_rasters["cl_$(cl)"][:,end:-1:1]
        writefile && write(outfile, class_rasters["cl_$(cl)"] )
    end
    return class_vars
end