#!/bin/bash

#set -x
set -e

help_func()
{
	echo "Bash script wrapper to copy all waveforms in a run log."
	echo 
	echo "Usage: ./copy_fullrun.sh -c <config_file> -l <log_file> -r <rsync options> -d <run_log>"
	echo "Options: "
	echo "-c: optional configuration file name, defaults to rsync_config.txt"
	echo "-l: optional log file name, defaults to rsync_log_fullruns_YYYYMMDD.txt"
	echo "-r: optional rsync run mode, defaults to avP [dry run mode: avPn]"
	echo "-d: optional run/DAQ log name, defaults to most recent completed run log"
	echo "	*should match to directory in config file"
	echo "-h: see help information"
}


# default config and output files
config_file="rsync_config.txt"
copy_log="rsync_log_fullruns_$(date +"%Y%m%d").txt"

# default rsync mode
rsync_mode="avP"

# override defaults with any user input
while getopts ":c:l:r:d:" option; do
	case $option in
		c) # config file
			config_file=$OPTARG;;
		l) # log file
			copy_log=$OPTARG;;
		r) # rsync mode
			rsync_mode=$OPTARG;;
		d) # run log
			run_log=$OPTARG;;
		\?) #invalid input
			echo "Error: invalid option entered."
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
if [ ! f"$copy_log" ]; then touch $copy_log; fi # make log file if it does not exist; can append to existing log

log_func "---------------------------------"
log_func "Single run data copier started"
log_func "---------------------------------"
log_func "Copying data files to: ${USER}@${HOST}:${TARGET}"

# if no run log is given, search for newest completed run log
if [[ -z "$run_log" ]]; then
	log_func "Searching for newest completed run log in ${RUN_LOG_DIR}..."
	counter=1
	run_log=$(ls -1 ${RUN_LOG_DIR}/*.log | sed 's#.*/##' | head -$((counter)) | tail -1)
	
	# check if run log is completed
	while true; do
		# two run completion statements for two PMT run; could be amended for variable no of PMTs
		if [[ "$(grep "log_run_completion:165" ${run_log} | wc -l)" -lt 2 ]]; then
			log_func "${run_log} is incomplete, searching for a completed run log..."
			prev_log=$run_log
			counter=$((counter+1))
			run_log=$(ls -1 ${RUN_LOG_DIR}/*.log | sed 's#.*/##' | head -$((counter)) | tail -1)
			# check if end of folder has been reached, exit if so
			if [[ "$prev_log" == "$run_log" ]]; then
				echo "No completed run logs found in ${RUN_LOG_DIR}. Please check configuration and try again."
				exit
			fi
		else
			break
		fi
	done
else
	# verify run log is in given directory
	if [[ ! -f ${RUN_LOG_DIR}/${run_log} ]]; then 
		log_func "Error: ${run_log} not found in ${RUN_LOG_DIR}, exiting."
		exit
	fi

	# verify given run file is complete
	if [[ "$(grep "log_run_completion:165" ${run_log} | wc -l)" -lt 2 ]]; then
		log_func "${run_log} was found to be incomplete - proceed with copying files anyway?"
		log_func "Warning! This may mean some wavesaves are not copied if run log is still being written to."
		# user verification to continue copying an incomplete run file
		while true; do
			read -p "Continue? Y/N: " prompt
			case $prompt in
				[Yy]* ) log_func "Proceeding..."; break;;
				[Nn]* ) log_func "Exiting data copier."; exit;;
				* ) log_func "Invalid input; enter Y to continue or N to exit."
			esac
		done
	fi	
fi

# read wavesave files written in run log
wavedump=$(grep -e "organize_files:522" ${run_log})

# create list of wavesave files
if [[ -f full_list.txt ]]; then rm full_list.txt; fi
touch full_list.txt
while IFS= read -r line; do
	line_arr=($line)
	echo "${line_arr[-1]#*WaveSaves/}" >> full_list.txt
	data_dir="${line_arr[-1]%scan_*}"
done <<< "$wavedump"

log_func "Found $(wc -l < full_list.txt) wavesave files, beginning to copy."
log_func "Files already present in ${TARGET} will be ignored."

# rsync with full file list; duplicates will be ignored
rsync -${rsync_mode} --ignore-existing --files-from=full_list.txt ${data_dir} ${USER}@${HOST}:${TARGET} | tee -a $copy_log

rm full_list.txt
log_func "All files copied to ${TARGET}, closing data copier."
log_func "---------------------------------"
