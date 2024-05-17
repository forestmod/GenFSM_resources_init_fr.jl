

function impute_X(data_path,X;force=false,verbosity=1)
    verbosity >= 1 && println("Iputing missing values..")
    dest = joinpath(data_path,"temp","full_X.jld")

    if ispath(dest) && !force 
        return JLD2.load(dest, "full_X")
    end

    if !isdir(joinpath(data_path,"temp"))
        mkdir(joinpath(data_path,"temp"))
    end

    #mod = RFImputer(n_trees=30,max_depth=10,recursive_passages=2)
    mod = UniversalImputer(estimator=DecisionTree.RandomForestRegressor(max_depth=10,n_trees=10),
                       fit_function = DecisionTree.fit!, predict_function=DecisionTree.predict,
                       recursive_passages=3)
    X_full_matrix = fit!(mod,Matrix(X))
    X_full = DataFrame(X_full_matrix,names(X))

    JLD2.jldopen(dest, "w") do f
        f["full_X"] = X_full
    end

    return X_full
end


function get_nn_trained_model(xtrain,ytrain,xval,yval;force=false,model_file="models.jld",maxepochs=5,scmodel=Scaler(),verbosity=STD)
    #model_file="models.jld"
    #force = false
    #xtrain = xtrain_s
    #sditrain = sditrain_s
    #stemntrain = stemntrain_s
    #epochs=[5,5,5]
    #verbosity = STD

    if !force 
        models = model_load(model_file)
        haskey(models,"bml_nnmodel") && return models["bml_nnmodel"]
    end

    # Prestep: scaling
    xtrain_s     = predict(scmodel,xtrain)
    xval_s       = predict(scmodel,xval)

    verbosity >= STD && @info "Training vol model.."
    #=
    # Define the Artificial Neural Network model
    l1_age  = ReplicatorLayer(8)
    l1_sp   = ReplicatorLayer(8)
    l1_soil = DenseLayer(44,60, f=relu)
    l1_oth  = DenseLayer(4,6, f=relu)
    l1      = GroupedLayer([l1_age,l1_sp,l1_soil,l1_oth])

    l2_age  = DenseLayer(8,3, f=relu)
    l2_sp   = DenseLayer(8,3, f=relu)
    l2_soil = DenseLayer(60,5, f=relu)
    l2_oth  = ReplicatorLayer(6)
    l2      = GroupedLayer([l2_age,l2_sp,l2_soil,l2_oth])

    l3_age  = ReplicatorLayer(3)
    l3_sp   = ReplicatorLayer(3)
    l3_soiloth = DenseLayer(11,11)
    l3      =  GroupedLayer([l3_age,l3_sp,l3_soiloth])

    l4 = DenseLayer(17,17, f=relu)
    l5 = DenseLayer(17,1, f=relu)
    nnm = NeuralNetworkEstimator(layers=[l1,l2,l3,l4,l5], batch_size=16, epochs=1, verbosity=verbosity) 
    =#
    nnm = NeuralNetworkEstimator( batch_size=16, epochs=1, verbosity=verbosity)

    rmes_train = Float64[]
    rmes_test  = Float64[] 
    for e in 1:maxepochs
        verbosity >= STD && @info "Epoch $e ..."
        # Train the model (using the ADAM optimizer by default)
        fit!(nnm,xtrain_s,ytrain) # Fit the model to the (scaled) data
        ŷtrain         = predict(nnm,xtrain_s) 
        ŷval           = predict(nnm,xval_s ) 
        rme_train      = relative_mean_error(ytrain,ŷtrain)  # 0.1517 # 0.1384 # 0.165
        rme_test       = relative_mean_error(yval,ŷval) 
        push!(rmes_train,rme_train)
        push!(rmes_test,rme_test)
    end
    display(plot([rmes_train[2:end] rmes_test[2:end]],title="Rel mean error per epoch", labels=["train rme" "test rme"]))
    display(plot(info(nnm)["loss_per_epoch"][2:end],title="Loss per epoch", label=nothing))

    model_save(model_file,true;bml_nnmodel=nnm)
    return nnm

end


function get_rf_trained_model(xtrain,ytrain;force=false,model_file="models.jld",verbosity=STD)
    #DecisionTree.fit!(rfmodel,fit!(Scaler(),xtrain),ytrain)
    #ŷtrain     = DecisionTree.predict(rfmodel,fit!(Scaler(),xtrain)) 
    #ŷtest      = DecisionTree.predict(rfmodel,fit!(Scaler(),xtest)) 

    models = model_load(model_file)
    (haskey(models,"bml_rfmodel") && !force ) && return models["bml_rfmodel"]
    # Using Random Forest model
    rfmodel = RandomForestEstimator(max_depth=20,verbosity=verbosity)
    # rfmodel = DecisionTree.RandomForestRegressor()
    fit!(rfmodel,xtrain,ytrain)
    model_save("models.jld",false;bml_rfmodel=rfmodel)
    return rfmodel

end


function get_estvol(x_s,mod,nAgeClasses,nSpgrClasses;force=false,data_file="estvol.csv")
    if ispath(data_file) && !force 
        return CSV.read(data_file,DataFrame)
    end
    estvol = DataFrame(r=Int64[],c=Int64[],ecoreg=Int64[],spgr=Int64[],agegr=Int64[],estvol=Float64[])
    x_mod = copy(x_s)
    for px in 1:size(x_mod,1), is in 1:nSpgrClasses, ia in 1:nAgeClasses, #size(X_full,1)
        r = X_full.R[px]
        c = X_full.C[px]
        ecoreg_px = ecoregion_full[px]
        spgr = is
        agegr = ia
        # modifying the record that we use as feature to predict the volumes
        x_mod[px,1:nAgeClasses] .= 0.0
        x_mod[px,1+nAgeClasses:nAgeClasses+nSpgrClasses] .= 0.0
        x_mod[px,ia] = 1.0
        x_mod[px,is+nAgeClasses] = 1.0

        evol = predict(mod,x_mod[px,:]')[1]
        #evol= 1.0
        push!(estvol,[r,c,ecoreg_px,spgr,agegr,evol])
    end
    CSV.write("estvol.csv",estvol)
    return estvol
end
