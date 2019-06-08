include(joinpath(@__DIR__, "..", "..", "..", "MLMML", "MLMML.jl"))
module CESMCORE_MLMML

    include("Workspace_MLMML.jl")
    include(joinpath(@__DIR__, "..", "..", "..", "share", "RecordTool.jl"))
    include(joinpath(@__DIR__, "..", "..", "..", "share", "AppendLine.jl"))

    using Formatting
    using ..NetCDFIO
    using ..MLMML
    using NCDatasets
    using .RecordTool

    name = "MLMML"

    days_of_mon = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    mutable struct MLMML_DATA
        casename    :: AbstractString
        map         :: NetCDFIO.MapInfo
        occ         :: MLMML.OceanColumnCollection

        x2o         :: Dict
        o2x         :: Dict

        configs       :: Dict

        output_vars :: Dict
        wksp        :: Workspace

        recorders   :: Dict
    end


    function init(;
        casename     :: AbstractString,
        map          :: NetCDFIO.MapInfo,
        t            :: AbstractArray{Integer},
        configs      :: Dict,
        read_restart :: Bool,
    )

        init_file = (haskey(configs, "init_file")) ? configs["init_file"] : nothing

        # If `read_restart` is true then read restart file: configs["rpointer_file"]
        # If not then initialize ocean with default profile if `initial_file`
        # is "nothing", with `init_file` if it is nonempty.

        if read_restart

            println("`read_restart` is on")

            if ! ("rpointer_file" in keys(configs))
                throw(ErrorException("Cannot find `rpointer_file` in configs!"))
            end

            if !isfile(configs["rpointer_file"])
                throw(ErrorException(configs["rpointer_file"] * " does not exist!"))
            end
            
            println("Going to read restart pointer file: ", configs["rpointer_file"])

            open(configs["rpointer_file"], "r") do file
                init_file = readline(file)
            end

            if !isfile(init_file)
                throw(ErrorException(format("Initial file \"{:s}\" does not exist!", init_file)))
            end
 
        end


        if typeof(init_file) <: AbstractString

            println("Initial ocean with profile: ", init_file)
            occ = MLMML.loadSnapshot(init_file)
        
        else

            throw(ErrorException("Variable `init_file` is absent in `configs`."))

        end

        wksp = Workspace(occ.Nx, occ.Ny, occ.Nz_bone)

        x2o = Dict(
            "SWFLX"  => wksp.swflx,
            "NSWFLX" => wksp.nswflx,
            "TAUX"  => wksp.taux,
            "TAUY"  => wksp.tauy,
            "IFRAC" => wksp.ifrac,
            "FRWFLX" => wksp.frwflx,
        )

        o2x = Dict(
            "SST"      => occ.T_ML,
            "QFLX2ATM" => occ.qflx2atm,
        )

        output_vars = Dict(
            #=
            "rain"      => wksp.frwflx,
            "mld"       => occ.h_ML,
            "sst"       => occ.T_ML,
            "qflx2atm"  => occ.qflx2atm,
            "sumflx"    => wksp.sumflx,
            "fric_u"    => wksp.fric_u,
            "ifrac"     => wksp.ifrac,
            =#
        )
        
        recorders = Dict()

        for rec_key in ["daily_record", "monthly_record"]
            if configs[rec_key]
                 recorder = RecordTool.Recorder(
                    Dict(
                        "Nx" => occ.Nx,
                        "Ny" => occ.Ny,
                        "Nz_bone" => occ.Nz_bone,
                    ), [
                        ("T",     occ.Ts, ("Nx", "Ny", "Nz_bone")),
                        ("S",     occ.Ss, ("Nx", "Ny", "Nz_bone")),
                        ("MLD",   occ.h_ML, ("Nx", "Ny")),
                    ]
                )

                recorders[rec_key] = recorder
               
            end
        end

        return MLMML_DATA(
            casename,
            map,
            occ,
            x2o,
            o2x,
            configs,
            output_vars,
            wksp,
            recorders,
        )

    end

    function run(
        MD            :: MLMML_DATA;
        t             :: AbstractArray{Integer},
        t_cnt         :: Integer,
        t_flags       :: Dict,
        Δt            :: Float64,
        substep       :: Integer,
        write_restart :: Bool,
    )

        include(joinpath(@__DIR__, "..", "..", "common_record_code.jl"))

        wksp = MD.wksp

        wksp.nswflx .*= -1.0
        wksp.swflx  .*= -1.0

        #wksp.sumflx[:, :]  = wksp.nswflx
        #wksp.sumflx      .+= wksp.swflx
        
        wksp.fric_u .= sqrt.(sqrt.((wksp.taux).^2.0 .+ (wksp.tauy).^2.0) / MLMML.ρ)
        wksp.weighted_fric_u .*= (1.0 .- wksp.ifrac)

        MLMML.stepOceanColumnCollection!(
            MD.occ;
            fric_u = wksp.weighted_fric_u,
            swflx  = wksp.swflx,
            nswflx = wksp.nswflx,
            frwflx = wksp.frwflx,
            Δt     = Δt,
            do_diffusion = (substep == MD.configs["substeps"]),
        )

        if write_restart
            restart_file = format("restart.ocn.{:04d}{:02d}{:02d}_{:05d}.nc", t[1], t[2], t[3], t[4])
            MLMML.takeSnapshot(MD.occ, restart_file)
             
            open(MD.configs["rpointer_file"], "w") do file
                write(file, restart_file)
            end

            println("(Over)write restart pointer file: ", MD.configs["rpointer_file"])
            println("Output restart file: ", restart_file)
        end

    end

    function final(MD::MLMML_DATA)
        
    end

end
