mutable struct State
    
    # total velocity, buoyancy
    u_c  :: AbstractArray{Float64, 3}
    v_c  :: AbstractArray{Float64, 3}
    b_c  :: AbstractArray{Float64, 3}

    u_f  :: AbstractArray{Float64, 3}
    v_f  :: AbstractArray{Float64, 3}
    w_f  :: AbstractArray{Float64, 3}
    b_f  :: AbstractArray{Float64, 3}


    X  :: AbstractArray{Float64, 4}   # all tracers, 1 is T, 2 is S
    T  :: AbstractArray{Float64, 3}   # dimensions in Nz_f grid
    S  :: AbstractArray{Float64, 3} 

    Φ  :: AbstractArray{Float64, 2}
    
    # barotropic component
    U  :: AbstractArray{Float64, 2}
    V  :: AbstractArray{Float64, 2}
    B  :: AbstractArray{Float64, 2}

    # Baroclinic component
    u  :: AbstractArray{Float64, 3}
    v  :: AbstractArray{Float64, 3}
    b  :: AbstractArray{Float64, 3}

    # Exception 
    τx  :: AbstractArray{Float64, 2}  # on T grid
    τy  :: AbstractArray{Float64, 2}  # on T grid

    function State(env, datakind)

        Nx = env.Nx
        Ny = env.Ny
        Nz_c = env.Nz_c
        Nz_f = env.Nz_f

        u_c = allocate(datakind, Float64, Nz_c, Nx, Ny)
        v_c = allocate(datakind, Float64, Nz_c, Nx, Ny+1)

        u_f = allocate(datakind, Float64, Nz_f, Nx, Ny)
        v_f = allocate(datakind, Float64, Nz_f, Nx, Ny+1)
        w_f = allocate(datakind, Float64, Nz_f+1, Nx, Ny)

        b_c = allocate(datakind, Float64, Nz_c, Nx, Ny)
        b_f = allocate(datakind, Float64, Nz_f, Nx, Ny)
        
        NX = 2 + env.NX_passive
        X = allocate(datakind, Float64, Nz_f, Nx, Ny, NX)
        T = view(X, :, :, :, 1)
        S = view(X, :, :, :, 2)

        Φ = allocate(datakind, Float64, Nx, Ny)
        
        U = allocate(datakind, Float64, Nx, Ny  )
        V = allocate(datakind, Float64, Nx, Ny+1)
        B = allocate(datakind, Float64, Nx, Ny)

        u = copy(u_c)
        v = copy(v_c)
        b = copy(b_c)

        τx = copy(Φ)
        τy = copy(Φ)

        return new(
            u_c, v_c, b_c,
            u_f, v_f, w_f, b_f,
            X, T, S,
            Φ, U, V, B,
               u, v, b,
            τx, τy,
        )
        
    end
end



