function init!(
    ocn_env = Union{String, OceanEnv},
)

    # TODO
    ocn_env = (typeof(ocn_env) == String) ? loadOcnEnv(env) : ocn_env

    shared_data    = SharedData(ocn_env)
    job_dist_info  = JobDistributionInfo(ocn_env; overlap=2)

    model = Model(
        ocn_env,
        shared_data,
        job_dist_info,
    )

    println("Register Shared Data") 
    registerSharedData!(model)
    
    # Potential redundant: seems like shared_data is already doing this
    #ocn_state      = OcnState(shared_data)


    println("Creating slaves on nodes")
    @sync let

        @spawnat job_dist_info.dyn_slave_pid let
            global dyn_slave = PUHSOM.DynSlave(ocn_env, shared_data)

            PUHSOM.setupBinding!(dyn_slave)

        end
        
        for (p, pid) in enumerate(job_dist_info.tmd_slave_pids)
            @spawnat pid let
                global tmd_slave = PUHSOM.TmdSlave(
                    ocn_env,
                    shared_data,
                    job_dist_info.y_split_infos[p],
                )

                PUHSOM.setupBinding!(tmd_slave)
            end
        end
    end

    println("Slave created and data exchanger is set.")
    readline()

    #=

    if restart_file != nothing
        loadRestart(restart_file, shared_data)
    end
    =#

    println("Testing syncing")
    syncOcean(model, from=:master, to=:all)
    
    println("Pass!")
    readline()

end


function syncOcean(
    model:: Model;
    from :: Symbol,
    to   :: Symbol,
)

    jdi = model.job_dist_info

    @sync let

        @spawnat jdi.dyn_slave_pid let

            PUHSOM.syncData!(dyn_slave.data_exchanger, :pull)

        end

    end
#=
    for (p, pid) in enumerate(job_dist_info.tmd_slave_pids)
        @spawnat pid let
            global tmd_slave = PUHSOM.TmdSlave(
                ocn_env,
        end

    end=#
end

#=
function run!(
    model,
    write_restart,
)

    load ... 
    substep_dyn
    substep_tcr
    substep_mld

    # Currently mld_core does not need info from
    # dyn_core so we do not need to pass dyn fields
    # to mld core
    for t=1:substep_dyn
        step_dyn(dyn_slaves)
    end
    syncOcean(from = :dyn_slave, to = :tcr_slave, shared_data)
 
    # this involves passing tracer through boundaries
    # so need to sync every time after it evolves
    for t=1:substep_tcr
        step_tcr(tcr_slaves)
        if t != substep_tcr
            syncOcean(from = :tcr_slave, to = :tcr_slave, shared_data)
        else
            syncOcean(from = :tcr_slave, to = :mld_slave, shared_data)
        end
    end

    # Supposedly MLD dynamics changes dyn and tcr fields vertically
    # so it only sync by the end of simulation and sync to
    # all other components
    for t=1:substep_mld
        step_mld(mld_slaves)
    end
    syncOcean(from = :mld_slave, to = :all, shared_data)
   
    if write_restart
        writeRestart(
            dyn_slave,
            tcr_slave,
            mld_slave, 
        )
    end
     
end

=#

function registerSharedData!(model::Model)

    descs_X = (
        (:X,     :fT, :zxy, Float64),
        (:X_ML,  :sT, :xy,  Float64),
    )
 
    descs_noX = (

        (:h_ML,  :sT, :xy,  Float64),
        (:FLDO,  :sT, :xy,    Int64),
        
        # These are used by dyn_core 
        (:u_c,   :cU, :xyz, Float64),
        (:v_c,   :cV, :xyz, Float64),
        (:b_c,   :cT, :xyz, Float64),
        (:Φ  ,   :sT, :xy,  Float64),

        # Forcings and return fluxes to coupler
        (:SWFLX,   :sT, :xy,  Float64),
        (:NSWFLX,  :sT, :xy,  Float64),
        (:TAUX,    :sT, :xy,  Float64),
        (:TAUY,    :sT, :xy,  Float64),
        (:IFRAC,   :sT, :xy,  Float64),
        (:FRWFLX,  :sT, :xy,  Float64),
        (:VSFLX,   :sT, :xy,  Float64),
        (:QFLX_T,  :sT, :xy,  Float64),
        (:QFLX_S,  :sT, :xy,  Float64),
        (:T_CLIM,  :sT, :xy,  Float64),
        (:S_CLIM,  :sT, :xy,  Float64),
        (:MLT,     :sT, :xy,  Float64),
    ) 


    for (id, grid, shape, dtype) in descs_X
        regVariable!(model.shared_data, model.env, id, grid, shape, dtype, has_Xdim=true)
    end

    for (id, grid, shape, dtype) in descs_noX
        regVariable!(model.shared_data, model.env, id, grid, shape, dtype, has_Xdim=false)
    end




end


function loadData!()
end