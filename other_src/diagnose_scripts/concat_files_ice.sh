#!/bin/bash

if [ -f $ice_concat ]; then

    echo "$ice_concat already exists. Skip."

else

    echo "Concat ice files of $res_casename"

    # ice variables
    cd $ice_hist_dir 
    eval "$(cat <<EOF
    ncrcat -O -v aice,hi $res_casename.cice.h.{$beg_year..$end_year}-{01..12}.nc $ice_concat

EOF
    )"

    cd $wdir
    julia $script_coordtrans_dir/transform_data.jl --s-file=$ice_concat --d-file=$ice_concat_rg --w-file=$wgt_file --vars=aice,hi --x-dim=ni --y-dim=nj --t-dim=time 

fi