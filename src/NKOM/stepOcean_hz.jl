using Statistics

function stepOcean_hz!(
    ocn  :: Ocean;
    cfgs...
)

    # Unpacking
    substeps      = cfgs[:substeps]
    Δt            = cfgs[:Δt]

    dt = Δt / substeps


    # Pseudo code
    # 1. assign velocity field
    # 2. calculate temperature & salinity flux
    # 3. calculate temperature & salinity flux divergence
    # Gov eqn adv + diff: ∂T/∂t = - 1 / (ρ H1) ( ∇⋅(M1 T1) - (∇⋅M1) Tmid )
  
    # ===== [BEGIN] Non responsive part (substeps non-effective ) =====
 
    # Transform input wind stress vector first
    DisplacedPoleCoordinate.project!(ocn.gi, ocn.in_flds.taux, ocn.in_flds.tauy, ocn.τx, ocn.τy, direction=:Forward)

    for grid_idx in 1:size(ocn.valid_idx)[2]

        i = ocn.valid_idx[1, grid_idx]
        j = ocn.valid_idx[2, grid_idx]

        ϵ = 1e-6 #ocn.ϵs[i, j]
        f = ocn.fs[i, j]

        τx = ocn.τx[i, j]
        τy = ocn.τy[i, j]

        h_ML = ocn.h_ML[i, j]
        Nz   = ocn.Nz[i, j] 
        s2ρh = ρ * h_ML * (ϵ^2.0 + f^2.0)

        ek_u = (ϵ * τx + f * τy) / s2ρh
        ek_v = (ϵ * τy - f * τx) / s2ρh

        FLDO = ocn.FLDO[i, j]

        if FLDO == -1
            ocn.u[:, i, j] .= ek_u
            ocn.v[:, i, j] .= ek_v
        else
            ocn.u[1:FLDO-1, i, j] .= ek_u
            ocn.v[1:FLDO-1, i, j] .= ek_v

            ocn.u[FLDO:Nz, i, j] .= 0.0
            ocn.v[FLDO:Nz, i, j] .= 0.0
        end
        


    end
        
    # Calculate ∇⋅v
    for k=1:ocn.Nz_bone
        DisplacedPoleCoordinate.DIV!(ocn.gi, ocn.lays.u[k],  ocn.lays.v[k],  ocn.lays.div[k])
    end

    # Calculate w
    for grid_idx in 1:size(ocn.valid_idx)[2]

        i = ocn.valid_idx[1, grid_idx]
        j = ocn.valid_idx[2, grid_idx]

        Nz = ocn.Nz[i, j]
        ocn.w[1, i, j] = 0.0
        for k = 2:Nz+1
            ocn.w[k, i, j] = ocn.w[k-1, i, j] + ocn.div[k-1, i, j]
        end
    end

    # ===== [END] Non responsive part =====


    # ===== [BEGIN] Responsive part (substpes effective) =====

    tmpflx = zeros(Float64, ocn.Nz_bone)
    tmpqs  = zeros(Float64, ocn.Nz_bone)

    for substep = 1:substeps 

        for grid_idx in 1:size(ocn.valid_idx)[2]

            i = ocn.valid_idx[1, grid_idx]
            j = ocn.valid_idx[2, grid_idx]

            for k=1:Nz
                ocn.uT[k, i, j] = ocn.u[k, i, j] * ocn.Ts[k, i, j]
                ocn.vT[k, i, j] = ocn.v[k, i, j] * ocn.Ts[k, i, j]
                ocn.uS[k, i, j] = ocn.u[k, i, j] * ocn.Ss[k, i, j]
                ocn.vS[k, i, j] = ocn.v[k, i, j] * ocn.Ss[k, i, j]
            end

        end

        for k=1:ocn.Nz_bone
            
            # Calculate ∇⋅(vT)
            DisplacedPoleCoordinate.DIV!(ocn.gi, ocn.lays.uT[k], ocn.lays.vT[k], ocn.lays.divTflx[k])

            # Calculate ∇⋅(vS)
            DisplacedPoleCoordinate.DIV!(ocn.gi, ocn.lays.uS[k], ocn.lays.vS[k], ocn.lays.divSflx[k])
            
            # Calculate ∇∇T, ∇∇S
            DisplacedPoleCoordinate.∇∇!(ocn.gi, ocn.lays.Ts[k], ocn.lays.∇∇T[k])
            DisplacedPoleCoordinate.∇∇!(ocn.gi, ocn.lays.Ss[k], ocn.lays.∇∇S[k])
        end


        # Vertical advection

        for grid_idx in 1:size(ocn.valid_idx)[2]

            i = ocn.valid_idx[1, grid_idx]
            j = ocn.valid_idx[2, grid_idx]


           

        end


    end

    
end



function vadv_upwind!(
    vadvs  :: AbstractArray{Float64, 1};
    ws     :: AbstractArray{Float64, 1},
    qs     :: AbstractArray{Float64, 1},
    Δzs    :: AbstractArray{Float64, 1},
    Nz     :: Integer,
)

    #
    # Array information:
    # 
    # length(ws)     == length(qs) or Nz + 1
    # length(Δzs)    == length(qs) or Nz - 1
    # length(qstmp)  == length(qs) or Nz
    # length(flxtmp) == length(qs) or Nz
    # 
    # Nz reveals if there is bottom of ocean
    # 

    # Extreme case: only one grid point
    if Nz <= 1
        return
    end

    if ws[1] > 0.0
        vadvs[1] = - ws[1] * (qs[1] - qs[2]) / Δzs[1]
    else
        vadvs[1] = 0.0
    end

    for k = 2:Nz-1
        if ws[k] > 0.0
            vadvs[k] = - ws[k] * (qs[k] - qs[k+1]) / Δzs[k]
        else
            vadvs[k] = - ws[k] * (qs[k-1] - qs[k]) / Δzs[k-1]
        end
    end

    # Do not update final layer
    vadvs[Nz] = 0.0 
    
end


"""

Calculation follows "MacCormack method" of Lax-Wendroff scheme.

Reference website:
  https://en.wikipedia.org/wiki/Lax%E2%80%93Wendroff_method#MacCormack_method

"""
function doZAdvection_MacCormack!(;
    Nz     :: Integer,
    qs     :: AbstractArray{Float64, 1},
    ws     :: AbstractArray{Float64, 1},
    Δzs    :: AbstractArray{Float64, 1},
    Δt     :: Float64,
    qstmp  :: AbstractArray{Float64, 1},
    flxtmp :: AbstractArray{Float64, 1},
)

    #
    # Array information:
    # 
    # length(ws)     == length(qs) or Nz + 1
    # length(Δzs)    == length(qs) or Nz - 1
    # length(qstmp)  == length(qs) or Nz
    # length(flxtmp) == length(qs) or Nz
    # 
    # Nz reveals if there is bottom of ocean
    # 

    # Step 1: calculate flux
    for k = 1:Nz
        flxtmp[k] = (ws[k] + ws[k+1]) / 2.0  * qs[k]
    end
   
    # Step 2: Calculate qs using flux from bottom
    for k = 1:length(qstmp)-1
        qstmp[k] = qs[k] - Δt / Δzs[k] * (flxtmp[k] - flxtmp[k+1])
    end
    # ignore flux at the last layer

    # Step 3: calculate updated flux
    for k = 1:Nz
        flxtmp[k] = (ws[k] + ws[k+1]) / 2.0  * qstmp[k]
    end
 
    # Step 4: Flux from top
    
    # First layer has no flux from above
    qs[1] = (qstmp[1] + qs[1]) / 2.0  - Δt / Δzs[1] / 2.0 * (- flxtmp[1])
    for k = 2:length(qstmp)-1
        qs[k] = (qstmp[k] + qs[k]) / 2.0 - Δt / Δzs[k-1] / 2.0 * (flxtmp[k-1] - flxtmp[k])
    end
   
    # Don't update qs[end] 
    
end

#=
"""

Calculation follows Lax-Wendroff scheme.

Reference website:
  https://en.wikipedia.org/wiki/Lax%E2%80%93Wendroff_method

"""
function doZAdvection_MacCormack!(;
    Nz     :: Integer,
    qs     :: AbstractArray{Float64, 1},
    ws     :: AbstractArray{Float64, 1},
    Δhs    :: AbstractArray{Float64, 1},
    Δzs    :: AbstractArray{Float64, 1},
    Δt     :: Float64,
    qstmp  :: AbstractArray{Float64, 1},
    flxtmp :: AbstractArray{Float64, 1},
)

    #
    # Array information:
    # 
    # length(ws)     == length(qs) or Nz    + 1
    # length(Δhs)    == length(qs) or Nz
    # length(Δzs)    == length(qs) or Nz    - 1
    # length(qstmp)  == length(qs) or Nz    + 1
    # length(flxtmp) == length(qs) or Nz    + 1
    # 
    # Nz reveals if there is bottom of ocean
    # 

    # Step 1: calculate flux
    for k = 1:Nz
        flxtmp[k] = (ws[k] + ws[k+1]) / 2.0  * qs[k]
    end

    # Step 2: Lax step. Calculate staggered qs
    qstmp[1] = qs[1] - Δt / Δzs[
    for k = 2:length(qstmp)
        qstmp[k] = 
    end
   
    # Step 2: flux from bottom
    for k = 1:length(qstmp)-1
        qstmp[k] = qs[k] - Δt / Δzs[k] * (flxtmp[k] - flxtmp[k+1])
    end
    # ignore flux at the last layer

    # Step 3: calculate updated flux
    for k = 1:Nz
        flxtmp[k] = (ws[k] + ws[k+1]) / 2.0  * qstmp[k]
    end
 
    # Step 4: Flux from top
    
    # First layer has no flux from above
    qs[1] = (qstmp[1] + qs[1]) / 2.0
    for k = 2:length(qstmp)-1
        qs[k] = (qstmp[k] + qs[k]) / 2.0 - Δt / Δzs[k-1] / 2.0 * (flxtmp[k-1] - flxtmp[k])
    end
   
    # Don't update qs[end] 
    
end
=#
