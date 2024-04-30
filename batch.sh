#!/bin/tcsh -xef

# execute via : (For B-shell, mkdir log before execution)
#   tcsh -xef batch.sh 2>&1 | tee log/batch.SUBJNAME.log
# tcsh -xef batch.sh LCT ORI201_LiCuntian enc polar 2>&1 | tee ./log/batch.ORI201_LiCuntian.log
#
# 2017.07.19
# WITHIN session, we transform the T1 image with INV(unWarpOutput) to align it to
# 	the raw FUNC images, so we don't warp the FUNC images within session. And the final T1 file
# 	is named as T1_al_epi_dist & T1_div_PD_dist $ T1_ns_al_epi ... So you should use
# 	these iamges as underlay to see the resutls within session.
# INTER sessions, use IntersessionAlign.sh
#
#
# 2017.07.14 bug fixed and tested on Mac OS
#
# by Jinyou Zou, jjzou_6@163.com
# Copyright All Rights Reserved
#

if (-d './log') then
  echo Get ouput 'in' folder log!
else
  mkdir ./log
endif

#########========= setup parameters ==============############
if ( $#argv > 0 ) then
    set subjName = $argv[1]
    set subj = $argv[2]
else
    set subj = VPL210_SunWeilai
    set subjName = SunWeilai
endif
# use absolute path
set datapath_prefix = /media/yulab/Data/fMRI_Trial_Design_with_freq
# set datapath_prefix = /home/yulab/Documents/fMRI_AFNI
set input_dir = $datapath_prefix/DATA/$subjName/$subj/to3dfile
set raw_dir = $datapath_prefix/DATA/$subjName/$subj/raw
# set physio_dir = /DATA8T/McGill_MPadapt/data_process/MRIdata/MPADAPT_S01/regressors/Physio
set output_dir = $datapath_prefix/RESULTS/$subjName/$subj


# set the name of functional run (do NOT contain blip correction run)
# we will resample all runs to the first run in case they have different FOV, so make sure
# that the 1st run is standard (e.g. 1st run should have the same FOV with reverse run)
cd $raw_dir
set runs = (`ls ?????{ori,polar,enc,freq,fen}* -d`)
# set runs = (`ls ?????{polar}* -d`)

# use 1 reverse_runs is enough (the run in the middle of the whole session is recommended))
# leave this blank if there is no reverse run
set reverse_runs = ()

# and make note of repetitions (TRs) per run
set frun_num = (`count -digits 2 1 $#runs`)

set tr_count_string = ''

foreach run ($runs)
    set runname = `echo $run | awk '{print substr($1, 6, 3)}'`
    set temptr = 0
    if ($runname == 'ori') then
        set temptr = 120
    endif
    if ($runname == 'fre') then
        set temptr = 120
    endif
    if ($runname == 'enc') then
        set temptr = 168
    endif
    if ($runname == 'pol') then
        set temptr = 190
    endif
    if ($runname == 'fen') then
        set temptr = 182
    endif
    if (temptr == 0) then
         echo no $run file, please add
         exit
    endif

    set tr_count_string = "$tr_count_string $temptr"
end
set tr_counts = ( $tr_count_string )
#
# set tr_counts = ( 190 )
# set this to () if you don't have physio signal records
# keep the same size and corresponding order as "runs"
set physio_regressors = ()


# now it can only be set to 0
set dummyScan = 0
# this is the resolution after volreg (also the final resolution)
set func_reso = 1

# set to 0 if you don't want it blured
set func_blur_fwhm = 0
set anat_reso = 1

# Because the convolution distortion in the two sides of PD image, we cut them out to get a
# better alignment. Plz check the results!
set PDcut_x = 40

# *** make sure that T1 and PD iamge are named as T1 and PD01/PD02..
# if there are more than 1 pd images, they will be averaged before any other processing
# if there is no PD images, set this to 0
set PDexist = 0

##### ======tcat remove the dummy scan###### minimize the effects due to the scanner onset.###
# apply 3dTcat to copy input dsets to results dir, while
# removing the TRs within dummyScan

echo "Copyright All Rights Reserved. by Dingzhi Hu"
echo "execution started: `date`"

# force compressing all data files to save disk space, while slowing down the processing a little
setenv AFNI_COMPRESSOR GZIP



if (1 == 1) then
mkdir -p $output_dir
mkdir -p $output_dir/stimuli

cd $output_dir

foreach run ( $frun_num )
    3dTcat -prefix pb00.$subj.epi$run.tcat $input_dir/${runs[${run}]}+orig'['$dummyScan'..$]' -overwrite
end

# also we copy the T1 and (average) PD image in the output directory
3dcopy $input_dir/T1+orig T1

# ================================ despike =================================
# apply 3dDespike to each run
foreach run ( $frun_num )
    3dDespike -NEW -nomask -overwrite -prefix pb00.$subj.epi$run.tcat \
        pb00.$subj.epi$run.tcat+orig
end

######========= deoblique the T1 to EPI ==============#####

3dTcat -prefix epi -overwrite pb00.$subj.epi01.tcat+orig'[0]'
3dWarp -oblique2card -prefix T1 -newgrid $anat_reso -overwrite T1+orig
# make cardinal T1 to match oblique epi data
3dWarp -card2oblique epi+orig -prefix T1 -newgrid $anat_reso -overwrite  T1+orig
3dAutobox -prefix T1 -input T1+orig. -overwrite
# change the head file of T1+orig
# replace transformation matrix in head file with cardinal matrix
3drefit -deoblique T1+orig

##3drefit the deoblique the epi runs data.
foreach run ($frun_num)
    3drefit -deoblique pb00.$subj.epi${run}.tcat+orig
end

######========= correct physio noise (with the method from AFNI_PROC) ==============#####
# For consistency, if there is no physio correction, 3dcopy it for further process
foreach run ( $frun_num )
    3dcopy pb00.$subj.epi$run.tcat pb01.$subj.epi$run.ricor
end

# =============== auto block: outcount 找到头动校准的参考volume（和其他volume差别最小）================
# data check: compute outlier fraction for each volume
touch out.pre_ss_epi_warn.txt
foreach run ( $frun_num )

    3dToutcount -automask -fraction -polort 3 -legendre                     \
                pb01.$subj.epi$run.ricor+orig > outcount.epi$run.1D

    1deval -a outcount.epi$run.1D -expr "1-step(a-0.1)" > rm.out.cen.epi$run.1D

    # outliers at TR 0 might suggest pre-steady state TRs
    if ( `1deval -a outcount.epi$run.1D"{0}" -expr "step(a-0.4)"` ) then
        echo "** TR #0 outliers: possible pre-steady state TRs in run $run" \
            >> out.pre_ss_epi_warn.txt
    endif

end

# catenate outlier counts into a single time series
cat outcount.epi*.1D > outcount_epiall.1D

# catenate outlier censor files into a single time series
cat rm.out.cen.epi*.1D > outcount_${subj}_censor.1D

# get run number and TR index for minimum outlier volume

set minindex = `3dTstat -argmin -prefix - outcount_epiall.1D\'`
set ovals = ( `1d_tool.py -set_run_lengths $tr_counts                       \
                          -index_to_run_tr $minindex` )
# save run and TR indices for extraction of vr_base_min_outlier
set minoutrun = $ovals[1]
set minouttr  = $ovals[2]
@ minouttr = $minouttr - 1
echo "min outlier: run $minoutrun, TR $minouttr" | tee out.min_outlier.txt

# ================================= tshift =================================
# time shift data so all slice timing is the same
foreach run ( $frun_num )
    3dTshift -tzero 0 -quintic -prefix pb02.$subj.epi$run.tshift \
             pb01.$subj.epi$run.ricor+orig -overwrite
    # resample the data in case the FOV is different across runs, also change the resolution to the final reso
    3dresample -master pb02.$subj.epi01.tshift+orig -dxyz $func_reso $func_reso $func_reso  \
             -inset pb02.$subj.epi$run.tshift+orig -prefix pb02.$subj.epi$run.tshift -overwrite
end


# ======extract volreg registration base=============##################
3dbucket -prefix vr_base_epi pb02.$subj.epi${minoutrun}.tshift+orig"[$minouttr]" -overwrite

#3dvolreg -overwrite -verbose -zpad 1 -base pb02.$subj.epi01.tshift+orig"[0]" -prefix vr_base_to_forward \
#		-1Dmatrix_save mat.vr_base_to_forward.aff12.1D vr_base_epi+orig

# now we use the vr_base as foward_base as well.

######============== 矫正phase encoding方向的EPI变形 =======================#####

foreach run ( $frun_num )
    # register each volume to the base
    3dvolreg -overwrite -verbose -zpad 1 -base vr_base_epi+orig          \
             -1Dfile dfile.epi$run.1D -prefix pb03.$subj.epi$run.volreg \
             -cubic                                       \
             -1Dmatrix_save mat.epi$run.vr.aff12.1D               \
             pb02.$subj.epi$run.tshift+orig
end

cat dfile.epi*.1D > dfile_epi.1D

## 1dplot看头动参数
#1dplot -volreg -dx 5 -xlabel Time dfile.epi.1D

# ================================== mask ==================================
# create 'full_mask' dataset (union mask)
foreach run ( $frun_num )
    3dAutomask -overwrite -dilate 1 -prefix rm.mask_epi$run pb03.$subj.epi$run.volreg+orig
end

# create union of inputs, output type is byte
3dmask_tool -overwrite -inputs rm.mask_epi*+orig.HEAD -union -prefix full_mask.$subj

3dAutobox -prefix full_mask.$subj -input full_mask.$subj+orig -overwrite

# apply full mask to functional data and autobox them
foreach run ( $frun_num )
    cp -T pb03.$subj.epi$run.volreg+orig.BRIK.gz pb03.$subj.epi$run.volreg+orig.backup.BRIK.gz
    cp -T pb03.$subj.epi$run.volreg+orig.HEAD pb03.$subj.epi$run.volreg+orig.backup.HEAD
    3dresample -master full_mask.$subj+orig -inset pb03.$subj.epi$run.volreg+orig \
            -prefix pb03.$subj.epi$run.volreg -overwrite
    # 3dcalc -a pb03.$subj.epi$run.volreg+orig -b full_mask.$subj+orig -expr 'a*b' -prefix pb03.$subj.epi$run.volreg -overwrite
    # 3dAutobox -prefix pb03.$subj.epi$run.volreg -input pb03.$subj.epi$run.volreg+orig -noclust -overwrite
end

# =================================align T1 to epi.mean==================================

# we transform the vr_base epi image with phase-distortion-correction matrix here for the
# alighment with T1 image. Other functional images will not be corrected untill finished the
# GLM or ERA

# # for e2a: compute anat alignment transformation to EPI registration base
3dSkullStrip -orig_vol -prefix T1_ns -input T1+orig -overwrite

## align T1_ns to epi
align_epi_anat.py -anat2epi -anat T1_ns+orig							\
   -anat_has_skull no -suffix _al_epi								\
   -epi vr_base_epi+orig -epi_base 0					\
   -epi_strip None											\
   -volreg off -tshift off


## align T1 to epi
3dAllineate -base T1+orig												\
                -input T1+orig											\
                -1Dmatrix_apply T1_ns_al_epi_mat.aff12.1D				\
                -mast_dxyz $anat_reso -quiet									\
                -prefix T1_al_epi

# ================================= spatial blur ==================================
if ( $func_blur_fwhm > 0 ) then
    foreach run ( $frun_num )
         3dmerge -1blur_fwhm $func_blur_fwhm -doall -prefix pb04.$subj.epi$run.blur pb03.$subj.epi$run.volreg+orig -overwrite
    end
else
    foreach run ( $frun_num )
         3dcopy -overwrite pb03.$subj.epi$run.volreg+orig pb04.$subj.epi$run.blur
    end
endif

# ================================= scale ==================================
# scale each voxel time series to have a mean of 100
# (be sure no negatives creep in)
# (subject to a range of [0,200])
#

## Scale with blurred dataset
foreach run ( $frun_num )
    3dTstat -overwrite -mean -prefix rm.mean_epi$run pb04.$subj.epi$run.blur+orig
    3dcalc -overwrite -a pb04.$subj.epi$run.blur+orig -b rm.mean_epi$run+orig \
        -c full_mask.$subj+orig                            \
        -expr 'c * min(200, a/b*100)*step(a)*step(b)'       \
        -prefix pb05.$subj.epi$run.scale.blur
end

# =========================== Using delay method =========================
waver -TR 1.003 -EXPR "(t/8)^0.3 * exp(-t/8)" -numout 319 -tstim `count 0 320 40` > ref_ts_MIONIRF.1D


# ======================== Using FFT+phase method ===============================

# ================================ 3dTproject to remove the none interest regressors [for ERA analysis] =================================

# get none interest regressors and cencor file

1d_tool.py -infile dfile_epi.1D -set_run_lengths $tr_counts                                   \
           -demean -write motion_epi_demean.1D -overwrite

1d_tool.py -infile dfile_epi.1D -set_run_lengths $tr_counts                                   \
           -derivative -demean -write motion_epi_deriv.1D -overwrite

1d_tool.py -infile dfile_epi.1D -set_run_lengths $tr_counts                                   \
    -show_censor_count -censor_prev_TR																\
    -censor_motion 0.3 motion_epi -overwrite

## ========================== finalize ==========================
# remove temporary files
rm -fr rm.*

echo "Copyright All Rights Reserved. by Jinyou Zou"
echo "execution finished: `date`"

setenv AFNI_COMPRESSOR gz
