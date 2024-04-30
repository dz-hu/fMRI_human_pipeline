#!/bin/tcsh -xef
echo "Copyright All Rights Reserved. by Dingzhi Hu"
echo "execution started: `date`"
setenv AFNI_COMPRESSOR GZIP

set starttime = `date`

set Lsubjlist = (BaiXinyue ChenJunyu JiaoMengyao \
    Kaidierya LiHuasong LinLing \
    LiYonglin MeiXinyang PuYue SongWeibin \
    SuHailun YangFan YuSiyue)

set Rsubjlist = (BaHanaer CaoLun ChenSiru GuYifan HeHaochen \
    JuNiansheng LiMingman NiWei ShangQingxin SunZheng \
    WangWeihan WangXuanyu XuXijing YangYingxue YanYujing \
    YanYutong YeKai)

set SpLsubjlist = (JiangDongxin   ChengYiran   LiJie   LiYajing   ZhangWenjia  \
    ShanYilin   YinJinwaner)

set subjNameList = ( $Lsubjlist $Rsubjlist $SpLsubjlist )
set datapath_prefix = /media/yulab/Data/fMRI_Trial_Design_with_freq

foreach subjName (ChenSiru)

    # scale each voxel time series to have a mean of 100
    # (be sure no negatives creep in)
    # (subject to a range of [0,200])
    set excute_dir = ${datapath_prefix}/RESULTS/${subjName}/${subjName}_surf_process
    set smoothsurf = smoothwm
    set blurFWMH = 0
    set output_dir = $excute_dir/$smoothsurf.${blurFWMH}
    cd $excute_dir/..
    set subSessions = (`ls VPL* -ld | grep ^d | awk '{print $9}'`)

    cd $output_dir
    set runtype = intersession
    if ( $runtype == intersession ) then
        set Mark = 'SPMG1IM'
        set Rmodel = $Mark
        cp -r ../../${subjName}_intersession/stimuli .
        cp ../../${subjName}_intersession/motion_epi* .
        foreach hem (lh rh)
            3dDeconvolve -input pb05.VPL{1,2}*.scale.blur*.${hem}.niml.dset  \
                  -censor motion_epi_censor.1D                         \
                  -polort A -float                                                       \
                  -num_stimts 20                                                         \
                  -stim_file 1 motion_epi_demean.1D'[0]' -stim_base 1 -stim_label 1 roll_01  \
                  -stim_file 2 motion_epi_demean.1D'[1]' -stim_base 2 -stim_label 2 pitch_01 \
                  -stim_file 3 motion_epi_demean.1D'[2]' -stim_base 3 -stim_label 3 yaw_01   \
                  -stim_file 4 motion_epi_demean.1D'[3]' -stim_base 4 -stim_label 4 dS_01    \
                  -stim_file 5 motion_epi_demean.1D'[4]' -stim_base 5 -stim_label 5 dL_01    \
                  -stim_file 6 motion_epi_demean.1D'[5]' -stim_base 6 -stim_label 6 dP_01    \
                  -stim_file 7 motion_epi_deriv.1D'[0]' -stim_base 7 -stim_label 7 roll_02   \
                  -stim_file 8 motion_epi_deriv.1D'[1]' -stim_base 8 -stim_label 8 pitch_02  \
                  -stim_file 9 motion_epi_deriv.1D'[2]' -stim_base 9 -stim_label 9 yaw_02    \
                  -stim_file 10 motion_epi_deriv.1D'[3]' -stim_base 10 -stim_label 10 dS_02  \
                  -stim_file 11 motion_epi_deriv.1D'[4]' -stim_base 11 -stim_label 11 dL_02  \
                  -stim_file 12 motion_epi_deriv.1D'[5]' -stim_base 12 -stim_label 12 dP_02  \
                  -stim_times_IM 13 stimuli/ori_T_pre.txt 'SPMG1' -stim_label 13 ori_T_pre\
                  -stim_times_IM 14  stimuli/ori_UT_pre.txt 'SPMG1' -stim_label 14 ori_UT_pre \
                  -stim_times_IM 15 stimuli/freq_T_pre.txt 'SPMG1' -stim_label 15 freq_T_pre \
                  -stim_times_IM 16 stimuli/freq_UT_pre.txt 'SPMG1' -stim_label 16 freq_UT_pre \
                  -stim_times_IM 17 stimuli/ori_T_post.txt 'SPMG1' -stim_label 17 ori_T_post\
                  -stim_times_IM 18 stimuli/ori_UT_post.txt 'SPMG1' -stim_label 18 ori_UT_post \
                  -stim_times_IM 19 stimuli/freq_T_post.txt 'SPMG1' -stim_label 19 freq_T_post \
                  -stim_times_IM 20 stimuli/freq_UT_post.txt 'SPMG1' -stim_label 20 freq_UT_post \
                  -jobs 8             \
                  -fout -tout -x1D X.$Mark.$runtype.xmat.1D  \
                  -xjpeg X.$Mark.$runtype.jpg  \
                  -x1D_uncensored X.$Mark.$runtype.nocensor.xmat.1D   \
                  -fitts fitts.$Mark.$runtype.${subjName}.${hem}.niml.dset   \
                  -errts errts.$Mark.$runtype.${subjName}.${hem}.niml.dset  \
                  -bucket stats.$Mark.$runtype.${subjName}.${hem}.niml.dset		\
                  -overwrite -noFDR
        end
   endif
end



echo SUCCESS
echo starttime: $starttime
echo endtime: `date`
