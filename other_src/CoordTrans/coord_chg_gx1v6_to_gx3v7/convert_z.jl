using NCDatasets
using Formatting

include("./MLMML_z_res.jl")
include("./interpolate.jl")

fn_i    = ARGS[1]
fn_o    = ARGS[2]
varname = ARGS[3]


missing_value = 1e20

ds_i    = Dataset(fn_i, "r")
ds_o    = Dataset(fn_o, "c")

Nx = ds_i.dim["Nx"]
Ny = ds_i.dim["Ny"]
Nz_MLMML = length(zs_MLMML) - 1

defDim(ds_o, "Nx", Nx)
defDim(ds_o, "Ny", Ny)
defDim(ds_o, "Nz", Nz_MLMML)
defDim(ds_o, "zs", length(zs_MLMML))
defDim(ds_o, "time", Inf)

for (varname, vardata, dims) in (
    ("lat", ds_i["lat"][:], ("Nx", "Ny",)),
    ("lon", ds_i["lon"][:], ("Nx", "Ny",)),
    ("zs", zs_MLMML, ("zs",)),
)
    println("varname: ", varname)
    v = defVar(ds_o, varname, Float64, dims)
    v[:] = vardata
end

old_data = replace(ds_i[varname][:], missing=>NaN)
new_data = zeros(Float64, Nx, Ny, Nz_MLMML)

new_data .= NaN

# interpolation function needs
# monotonic increasing function
depth_NCAR_LENS = - zs_mid_NCAR_LENS
depth_MLMML     = - zs_mid_MLMML


for i=1:Nx, j=1:Ny
   
    # detect rng
    valid_data_cnt = sum(isfinite.(old_data[i, j, :]))
 
    if valid_data_cnt == 0

        continue

    elseif valid_data_cnt == 1  # no interpolation at all
        
        println(format("Special case happens at (i, j) = ({},{})", i, j))
        new_data[i, j, :] .= old_data[i, j, 1]

    else

        new_data[i, j, :] = interpolate(
            depth_NCAR_LENS[1:valid_data_cnt], old_data[i, j, 1:valid_data_cnt],
            depth_MLMML;
            left_copy=true,
            right_copy=true,
        )

    end

end

new_var = defVar(ds_o, varname, Float64, ("Nx", "Ny", "Nz", "time"))
new_var.attrib["_FillValue"] = missing_value
new_var[:, :, :, 1] = new_data

close(ds_i)
close(ds_o)

