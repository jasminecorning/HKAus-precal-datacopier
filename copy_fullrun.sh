#!/bin/bash

#set -x
set -e

# help function
help_func()
{
	echo "Bash script wrapper to copy waveforms from a run log for a given run ID."
	echo "Runs in a loop so additional run IDs can be input following the initial call."
	echo 
	echo "Usage: ./copy_fullrun.sh -i <run_id> -c <config_file> -r <rsync options>"
	echo "Options: "
	echo "-i: required run ID to copy wavedump files for, in format YYYYMMDD_HHMMSS"
	echo "-c: optional configuration file name, defaults to rsync_config.txt"
	echo "-r: optional rsync run mode, defaults to avP [dry run mode: avPn]"
	echo "-h: see help information"
}

# copying function for a given run id
copy_main()
{
	# list run logs in directory starting from newest
	for run_log in $(ls -t ${RUN_LOG_DIR}/*.log); do
		proceed=0 # exit condition for no wavedumps
		# check for wavedump assosciated with given run ID
		if grep -qe ${run_id} ${run_log}; then
			all_run_id_match=$(grep -e "${run_id}" ${run_log})
			# search for line which organizes wavedump files into final folder
			wavedumps=$(echo "$all_run_id_match" | grep -e "✓ Organized" | awk '{print $NF}')
			if [[ -n "$wavedumps" ]]; then
				break
			else
				# proceed with warning if no file organization found
				log_func "Warning! ${run_id} found but no complete wavedumps verified. Do you wish to proceed anyway?"
				log_func "Some wavesaves may not be copied/may be corrupted if they are still being written."
				while true; do
					read -p "Continue? Y/N: " prompt
					case $prompt in
						[Yy]* ) log_func "Proceeding..."; proceed=1; break;;
						[Nn]* ) log_func "Exiting main data copier function."; return;;
						* ) log_func "Invalid input; enter Y to continue or N to exit."
					esac
				done
			fi
		else
			continue
		fi
	done

	# check if empty for no wavedumps found
	if [[ -z "$wavedumps" ]]; then
		if (( proceed )); then # user wants to proceed with incomplete wavedump records
			completed_files=$(echo "$all_run_id_match" | grep -e "Moved Ch" | awk '{print $NF}')
			# build wavedumps manually from all commmon folders with wavesave files saved inside
			touch tmp_files.txt
			for wavesave in $completed_files; do
				IFS="/" read -r -a file_folders <<< "$wavesave"
				file_dir="${file_folders[*]:0:${file_folders[@]}-1}"
				# add new save directory paths to temporary file
				grep -qxF "$file_dir" tmp_files.txt || echo "$file_dir" >> tmp_files.txt		
			done
			wavedumps=$(cat tmp_files.txt)
			rm tmp_files.txt
		else
			log_func "No eligible wavedumps found in ${RUN_LOG_DIR}. Please check configuration and try again."
			exit
		fi
	fi       

	# build target sub-directory with run ID and pmt ID
	if [[ "$RUN_TYPE" == "manual" ]]; then
		# currently require user to input PMT serial no. manually for this type of run
		while true; do
			read -p "Please enter PMT serial number as AAXXXX-A: " prompt
			PMT_SERIAL=$prompt
		done
	elif [[ "$RUN_TYPE" == "scan" ]]; then
		# obtain PMT serial no. from pathing
		IFS= read -r first_dir <<< "$wavedumps"
		IFS="/" read -r -a dir_folders <<< "$first_dir"
		PMT_SERIAL="${dir_folders[5]}"
	else
		log_func "${RUN_TYPE} not recognized, exiting."
		exit 0
	fi

	log_func "Matching file names in ${TARGET} will be ignored."
	counter=0
	rsync_counter=0
	# read wavesave files written in run log
	for wavedump in $wavedumps; do
		# get files for each separate wavedump (correlates typically to scan positions)
		wavedump_files=$(ls -1 ${wavedump})
		if [[ -f file_list.txt ]]; then rm file_list.txt; fi
		touch file_list.txt
		while IFS= read -r line;
		do
			echo "${line}" >> file_list.txt
		done <<< "$wavedump_files"	

		# build sub-directories for target server
		# based on analysis directory structure
		position_dir="${wavedump##*/}"
		target_sub_dir="${RUN_TYPE}_${run_id}/${PMT_SERIAL}/${position_dir}"
		
		log_func "Copying into sub-directory: ${target_sub_dir}"
		num_files=$(wc -l < file_list.txt)
		log_func "Found $num_files files, beginning to copy..."
		((counter += num_files)) # count files identified to transfer

		# run rsync to copy files
		OUTPUT=$(rsync -${rsync_mode} --stats --progress --ignore-existing --files-from=file_list.txt ${wavedump} ${USER}@${HOST}:${TARGET}/${target_sub_dir} | tee -a $copy_log)	
		file_count=$(echo "$OUTPUT" | grep "Number of regular files transferred:" | awk -F': ' '{print $2}' | tr -d ',')
		((rsync_counter += file_count)) # count successful transfers
	done

	log_func "Successfully copied ${rsync_counter}/${counter} files to ${TARGET}."
}

# default config and output files
config_file="rsync_config.txt"
copy_log="rsync_log_fullruns_$(date +"%Y%m%d").txt"

# default rsync mode
rsync_mode="avP"

# override defaults with any user input
while getopts ":c:l:r:i:" option; do
	case $option in
		c) # config file
			config_file=$OPTARG;;
		l) # log file
			copy_log=$OPTARG;;
		r) # rsync mode
			rsync_mode=$OPTARG;;
		i) # target run id
			run_id=$OPTARG;;
		\?) #invalid input
			help_func
			exit;;
	esac
done

# check for run ID passed - this is required on initial call
if [[ -z "$run_id" ]]; then
	echo "Error! Run ID must be specified."
	help_func
	exit
fi

log_func()
{
	echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a $copy_log
}

# get USER, HOST, TARGET, RUN_LOG_DIR from config file
source $config_file
if [ ! f"$copy_log" ]; then touch $copy_log; fi # make log file if it does not exist; can append to existing log

log_func "---------------------------------"
log_func "Full run data copier started."
log_func "---------------------------------"
log_func "Copying data files to: ${USER}@${HOST}:${TARGET}"

# copy file loop - continues asking for new run IDs until user exits
# (or invalid input provided)
while true; do
	copy_main
	read -p "Would you like to copy another run? Y/N: " prompt
	case $prompt in
		[Yy]* ) read -p "Please enter another run ID (YYYYMMDD_HHMMSS): " run_id;;
		[Nn]* ) log_func "Now closing data copier."; log_func "---------------------------------"; exit;;
		* ) log_func "Invalid input; closeing data copier."; log_func "---------------------------------"; exit;;
	esac
done
