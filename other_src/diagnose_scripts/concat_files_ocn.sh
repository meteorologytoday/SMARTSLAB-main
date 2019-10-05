#!/bin/bash

if [ -f $ocn_concat_rg ] && [ ! -f flag_concat_ocn ]; then

    echo "$ocn_concat_rg already exists. Skip."

else

    if [ ! -f $ocn_concat ]; then

        echo "Concat ocn files of $full_casename"
        cd $ocn_hist_dir

        eval "$(cat <<EOF
        ncrcat -O -v h_ML,T_ML $full_casename.ocn.h.monthly.{$concat_beg_year..$concat_end_year}.nc $ocn_concat
EOF
        )"

    fi

    echo "Transforming data..."

    cd $wdir
    julia $script_coordtrans_dir/transform_data.jl --s-file=$ocn_concat --d-file=$ocn_concat_rg --w-file=$wgt_file --vars=T_ML,h_ML --x-dim=Nx --y-dim=Ny --z-dim=Nz_bone --t-dim=time 

fi


