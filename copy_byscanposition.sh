#!/bin/bash

#set -x
set -e

help_func()
{
	echo "Bash script wrapper to monitor for new data files and copy them to another location"
	echo "!! Should be started in screen BEFORE data taking begins !!"
	echo "Script will only copy files from runs in progress"
       	echo 	
	echo "Usage: ./run_by_run.sh -c <config_file> -l <log_file> -r"
	echo "Options: "
	echo "-c: optional configuration file, defaults to rsync_config.txt"
	echo "-l: optional log file, defaults to rsync_log_YYYYMMDD.txt (YYYYMMDD is date script began running)"
	echo "-r: optional rsync run mode, defaults to avP [dry run mode: avPn]"
	echo "-h: see help information"
}

# default config and output files
date_started=$(date +"%Y%m%d")
config_file="rsync_config.txt"
copy_log="rsync_log_${date_started}.txt"

# default rsync run mode
rsync_mode="avP"

# override defaults with any user input
while getopts ":c:l:r:" option; do
	case $option in
		c) # config file
			config_file=$OPTARG;;
		l) # log file
			copy_log=$OPTARG;;
		r) # rsync dry run mode
			rsync_mode=$OPTARG;;
		\?) # invalid input
			help_func
			exit;;
	esac
done

log_func()
{
	echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a $copy_log
}

# get USER, HOST, TARGET, RUN_LOG_DIR from config file
source $config_file
if [ ! -f "$copy_log" ]; then touch $copy_log; fi # make log file if not exists; can append to existing log

log_func "---------------------------------"
log_func "Data copier started!"
log_func "---------------------------------"
log_func "Copying data files to: ${USER}@${HOST}:${TARGET}"
log_func "Checking ssh authorization for ${USER}@${HOST}..."

# check proper SSH key authentication is set up
# script MUST BE used with keys rather than passwords
ssh -q -o BatchMode=yes ${USER}@${HOST} exit
if [[ $? -ne 0 ]]; then
	log_func "Error with ssh authorization! Please ensure ssh key access is set-up for ${USER}@${HOST}."
	exit 1 # exit if ssh key not set up
else
	log_func "Authorization for ${USER}@${HOST} is good, continuing."
fi

break_timer=0

# continous loop
while true; do

	# last run log file by timestamp
	log_file=$(ls -1 ${RUN_LOG_DIR}/*.log | sed 's#.*/##' | head -1)
	log_func "Last run log modified: ${log_file}"

	# check if log file is for a completed run
	if [[ -n "$(grep "log_run_completion:165" ${log_file})" ]]; then
		log_func "Most recent run log is for a completed run, waiting for new run..."
		sleep 5m
		break_timer=$((break_timer+5))
		if [[ "$break_timer" -ge 60 ]]; then break; fi
		continue # return to top and look for a newer run log
	fi

	# line number of last completed wavedump for a single scan position
	last_wavedump=$(grep -n "organize_files:525" ${log_file} | tail -1 | cut -d ':' -f1)

	# return to loop start if no complete wavedumps in log file yet
	if [[ -z "$last_wavedump" ]]; then
		log_func "No complete wavedumps found in $log_file, waiting..."
		sleep 2m
		break_timer=$((break_timer+2))
		if [[ "$break_timer" -ge 60 ]]; then break; fi
		continue
	fi

	# read files written for completed wavedumps only
	channels_wavedump=$(head -n $((last_wavedump)) ${log_file} | grep -n "organize_files:522")

	# create list of all wavesave files saved
	touch full_list.txt
	while IFS= read -r line; do
		line_arr=($line)
		echo "${line_arr[-1]#*WaveSaves/}" >> full_list.txt
		data_dir="${line_arr[-1]%scan_*}"
	done <<< "$channels_wavedump"

	# create list of new wavesave files written since last copied
	if [ ! -f prev_list.txt ]; then touch prev_list.txt; fi # create previous list file if not existing
	comm -23 --nocheck-order full_list.txt prev_list.txt > copy_list.txt # check against previous list of wave files
	cat full_list.txt > prev_list.txt # overwrite file list
	rm full_list.txt

	# if no new files are present, wait for new wavedumps
	new_files=$(wc -l < copy_list.txt)
	if [[ "$new_files" == "0" ]]; then
		log_func "No new raw files found, waiting..."
		sleep 5m
		break_timer=$((break_timer+5))
		if [[ "$break_timer" -ge 60 ]]; then break; fi
		continue # return to loop start
	fi

	log_func "Found $(wc -l < copy_list.txt) new raw files, beginning to copy."
	# rsync with input file list
	rsync -${rsync_mode} --ignore-existing --files-from=copy_list.txt $data_dir ${USER}@${HOST}:${TARGET} | tee -a $copy_log
	
	# reset timer
	break_timer=5
	log_func "Rsync complete."
	sleep 5m
done

log_func "No new wavesaves found for 60 minutes, automatically closing data copier."
log_func "---------------------------------"

rm prev_list.txt
rm copy_list.txt

