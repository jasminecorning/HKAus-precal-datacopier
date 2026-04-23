# HyperK Australia PMT Pre-Calibration Data Copiers

Script package to easily transfer data from on-site Linux computer where data is acquired to an external server. Data can be copied continously as as runs are being completed or all at once after a run is completed. All copies are done using rsync.

## Scripts

- `copy_byscanposition.sh`: copy data continously during runs by searching for completed scan positions
- `copy_fullrun.sh`: copy all files listed in a run log file [option for full or partial runs]
- `rsync_config.txt`: example default configuration file

## Configuration

Configuration file should contain:
```
USER=username on remote server
HOST=remote server hostname
TARGER=target directory for data on remote server
RUN_LOG_DIR=directory with run logs on local machine
```

## Continous Mode

Run as:
```
./copy_byscanposition.sh
```

Run in rsync dry run mode for testing (no files copied):
```
./copy_byscanposition.sh -r avPn
```

Continous data copier `copy_byscanposition.sh` can be used with the following options:
- -c: custom configuration file name
- -l: custom file name for copy log (defaults to rsync_log_YYYYMMDD.log)
- -r: options for rsync (defaults to avP)

Continous data copier will close automatically after an hour or more of inactivity.

## Single Run Mode

Run as:
```
./copy_fullrun.sh
```

Run in rsync dry run mode for testing (no files copied):
```
./copy_fullrun.sh -r avPn
```

Single run data copier `copy_fullrun.sh` can be used with the following options:
- -c: custom configuration file name
- -l: custom file name for copy log (defaults to rsync_log_YYYYMMDD.log)
- -r: options for rsync (defaults to avP)
- -d: run log file (defaults to most recent completed run log)
	- *Ensure run log is in run log directory specified in configuration file.*

## Contact

Jasmine Corning, [jasmine.corning@unimelb.edu.au](mailto:jasmine.corning@unimelb.edu.au)
