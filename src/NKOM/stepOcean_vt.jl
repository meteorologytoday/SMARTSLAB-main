#using Statistics

function stepOcean_MLDynamics!(
    ocn   :: Ocean;
    cfgs...
)

    # Unpacking
    qflx_scheme   = cfgs[:qflx_scheme]
    use_h_ML      = cfgs[:use_h_ML]
    Δt            = cfgs[:Δt]
    do_convadjust = cfgs[:do_convadjust]
    rad_scheme    = cfgs[:rad_scheme]


    
    ifrac   = ocn.in_flds.ifrac

    taux    = ocn.in_flds.taux
    tauy    = ocn.in_flds.tauy
    fric_u  = ocn.fric_u

    swflx   = ocn.in_flds.swflx
    nswflx  = ocn.in_flds.nswflx
    frwflx  = ocn.in_flds.frwflx
    qflx    = ocn.in_flds.qflx

    #println(swflx, ";", nswflx)


    # It is assumed here that buoyancy has already been updated.
    @loop_hor ocn i j let

        zs = ocn.cols.zs[i, j]
        Nz = ocn.Nz[i, j]

        fric_u[i, j] = √( √(taux[i, j]^2.0 + tauy[i, j]^2.0) / NKOM.ρ)
        weighted_fric_u = fric_u[i, j] * (1.0 - ifrac[i, j])


        # Pseudo code
        # Current using only Euler forward scheme:
        # 1. Determine h at t+Δt
        # 2. Determine how many layers are going to be
        #    taken away by ML.
        # 3. Cal b at t+Δt for both ML and DO
        # 4. Detect if it is buoyantly stable.
        #    Correct it (i.e. convection) if it is not.
        # 5. If convection happens, redetermine h.

        # p.s.: Need to examine carefully about the
        #       conservation of buoyancy in water column


        #surf_Tnswflx = ( nswflx[i, j] + ( ( use_qflx ) ? qflx[i, j] : 0.0 )) / (ρ*c_p) 
        surf_Tnswflx = nswflx[i, j] / (ρ*c_p) 
        surf_Tswflx  = swflx[i, j] / (ρ*c_p)
        surf_Jflx    = g * α * surf_Tswflx
        surf_Sflx    = - frwflx[i, j] * ocn.S_ML[i, j]
        surf_bflx    = g * ( α * surf_Tnswflx - β * surf_Sflx )
        
        old_FLDO = ocn.FLDO[i, j]
        old_h_ML = ocn.h_ML[i, j]
        old_T_ML = ocn.T_ML[i, j]
        old_S_ML = ocn.S_ML[i, j]

        new_h_ML = old_h_ML

        if use_h_ML # h_ML is datastream

            new_h_ML = ocn.in_flds.h_ML[i, j]

        else        # h_ML is prognostic
 
            target_z = max( - old_h_ML - 30.0,  - ocn.h_ML_max[i, j])
            avg_D = - old_h_ML - target_z

            Δb = ( (avg_D > 0.0) ? ocn.b_ML[i, j] - (
                  OC_getIntegratedBuoyancy(ocn, i, j; target_z =   target_z)
                - OC_getIntegratedBuoyancy(ocn, i, j; target_z = - old_h_ML)
            ) / avg_D
            : 0.0 )

            # After convective adjustment, there still might
            # be some numerical error making Δb slightly negative
            # (the one I got is like -1e-15 ~ -1e-8). So I set a
            # tolarence δb = 3e-6 ( 0.001 K => 3e-6 m/s^2 ).
            if -3e-6 < Δb < 0.0
                Δb = 0.0
            end

            if Δb < 0.0
                FLDO = ocn.FLDO[i, j]
                println(format("({:d},{:d}) Averge sense Δb={:f}", i, j, Δb))
                println(format("({:d},{:d}) Jump sense Δb={:f}", i, j, (FLDO != -1) ? ocn.b_ML[i, j] - ocn.bs[FLDO, i, j] : 999 ))
            end

            new_h_ML, ocn.h_MO[i, j] = calNewMLD(;
                h_ML   = old_h_ML,
                Bf     = surf_bflx + surf_Jflx * ocn.R,
                J0     = surf_Jflx * (1.0 - ocn.R),
                fric_u = weighted_fric_u,
                Δb     = Δb,
                f      = ocn.fs[i, j],
                Δt     = Δt,
                ζ      = ocn.ζ,
                h_max  = ocn.h_ML_max[i, j],
                we_max = ocn.we_max,
            )
            
        end

        new_h_ML = boundMLD(new_h_ML; h_ML_max=ocn.h_ML_max[i, j], h_ML_min=ocn.h_ML_min[i, j])


        # ML
        #      i: Calculate integrated buoyancy that should
        #         be conserved purely through entrainment
        #     ii: Add to total buoyancy

        # If new_h_ML < old_h_ML, then the FLDO layer should get extra T or S due to mixing


        if new_h_ML < old_h_ML

            new_FLDO = getFLDO(zs=zs, h_ML=new_h_ML, Nz=Nz)

            if old_FLDO == -1

                ocn.Ts[new_FLDO:Nz, i, j] .= ocn.T_ML[i, j]
                ocn.Ss[new_FLDO:Nz, i, j] .= ocn.S_ML[i, j]

            else
                FLDO_Δz =  -zs[old_FLDO+1] - old_h_ML
                retreat_Δz =  old_h_ML - ( (new_FLDO == old_FLDO) ? new_h_ML : (-zs[old_FLDO]) )

                ocn.Ts[new_FLDO, i, j] = (
                    ocn.Ts[old_FLDO, i, j] * FLDO_Δz + ocn.T_ML[i, j] * retreat_Δz
                ) / (FLDO_Δz + retreat_Δz)

                ocn.Ss[new_FLDO, i, j] = (
                    ocn.Ss[old_FLDO, i, j] * FLDO_Δz + ocn.S_ML[i, j] * retreat_Δz
                ) / (FLDO_Δz + retreat_Δz)
            end
        end

        if_entrainment = new_h_ML > old_h_ML

        # Calculate the effect of entrainment on SSS
        new_int_S_ML = OC_getIntegratedSalinity(   ocn, i, j; target_z = -new_h_ML)
        new_S_ML = new_int_S_ML / new_h_ML
        ocn.dSdt_ent[i, j] = (if_entrainment) ? (new_S_ML - old_S_ML) / Δt : 0.0

        # Add in external surface flux effect on SSS
        new_S_ML = max( (new_int_S_ML - surf_Sflx * Δt) / new_h_ML, 0.0)

        # Calculate the effect of entrainment on SST
        new_int_T_ML = OC_getIntegratedTemperature(ocn, i, j; target_z = -new_h_ML)
        new_T_ML = new_int_T_ML / new_h_ML
        ocn.dTdt_ent[i, j] = (if_entrainment) ? (new_T_ML - old_T_ML) / Δt : 0.0

        # Add in external surface flux effect on SST. Shortwave radiation is not included yet
        new_T_ML = (new_int_T_ML - surf_Tnswflx * Δt) / new_h_ML

        # Q-flux 
        if qflx_scheme == :energy_flux

            new_T_ML -= qflx[i, j] * Δt / (ρ * c_p * new_h_ML)

        elseif qflx_scheme == :temperature_flux
            new_T_ML -= qflx[i, j] * Δt
        end

        # Update mixed-layer
        OC_setMixedLayer!(
            ocn, i, j;
            T_ML=new_T_ML,
            S_ML=new_S_ML,
            h_ML=new_h_ML,
        )

#            if ocn.FLDO[i, j] > 1 && ocn.T_ML[i, j] != ocn.Ts[1, i, j] 
#                println(format("UPDATE ML ERROR: ({},{}) has T_ML={:f} but Ts[1]={:f}", i, j, ocn.T_ML[i,j], ocn.Ts[1,i,j]))
#            end

        # Shortwave radiation
        if rad_scheme == :exponential
            FLDO = ocn.FLDO[i, j]
            ocn.T_ML[i, j] += - ocn.R * surf_Tswflx * Δt / new_h_ML
            ocn.Ts[1:((FLDO == -1) ? Nz : FLDO-1 ), i, j] .= ocn.T_ML[i, j]
            OC_doShortwaveRadiation!(ocn, i, j; Tswflx=(1.0 - ocn.R) * surf_Tswflx, Δt=Δt)

#            if ocn.FLDO[i, j] > 1 && ocn.T_ML[i, j] != ocn.Ts[1, i, j] 
#                println(format("RADIATION ERROR: ({},{}) has T_ML={:f} but Ts[1]={:f}", i, j, ocn.T_ML[i,j], ocn.Ts[1,i,j]))
#            end
        elseif rad_scheme == :step
            FLDO = ocn.FLDO[i, j]
            ocn.T_ML[i, j] += - surf_Tswflx * Δt / new_h_ML
            ocn.Ts[1:((FLDO == -1) ? Nz : FLDO-1 ), i, j] .= ocn.T_ML[i, j]
        end

        OC_updateB!(ocn, i, j)

        if do_convadjust
            OC_doConvectiveAdjustment!(ocn, i, j;)

#            if FLDO > 1 && ocn.T_ML[i, j] != ocn.Ts[1, i, j] 
#                println(format("CONV ERROR: ({},{}) has T_ML={:f} but Ts[1]={:f}", i, j, ocn.T_ML[i,j], ocn.Ts[1,i,j]))
#            end


        end


    end

end

function stepOcean_slowprocesses!(
    ocn :: Ocean;
    cfgs...
)

    Δt            = cfgs[:Δt]
    do_vert_diff  = cfgs[:do_vert_diff]
    do_horz_diff  = cfgs[:do_horz_diff]
    do_relaxation = cfgs[:do_relaxation]
    do_convadjust = cfgs[:do_convadjust]

    # Climatology relaxation
    if do_relaxation
        @loop_hor ocn i j let
            ocn.Q_clim[i, j] = OC_doNewtonianRelaxation_T!(ocn, i, j; Δt=Δt) *  ρc
            OC_doNewtonianRelaxation_S!(ocn, i, j; Δt=Δt)
        end
    end
    
    # Vertical diffusion
    if do_vert_diff
        @loop_hor ocn i j let
            OC_doDiffusion_EulerBackward!(ocn, i, j; Δt=Δt)
        end
    end

    if do_relaxation || do_vert_diff || do_horz_diff

        @loop_hor ocn i j let
            OC_updateB!(ocn, i, j)
        end

        if do_convadjust
            @loop_hor ocn i j let
                OC_doConvectiveAdjustment!(ocn, i, j;)
            end
        end

    end

end
