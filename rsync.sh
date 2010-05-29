#!/bin/bash

# rsync between two different servers - optimized for multiple cron jobs
# rsync.sh
# Copyright (C) 2008-2010  Brett Alton <brett.jr.alton@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# INFO:
# 	* you can either run this script using 'run' then 'push' or 'pull', you can install it using 'install' then 'push' or 'pull'  or you can choose the 'uninstall' option to remove previously installed files
#	* if rsync/ssh are both prompting you for your password and it should be automatic, run 'rsync.sh uninstall' and then try again

# DIRECTORIES CREATED:
# 	* $HOME/
#		* bin
#		* cron
#		* logs

# USAGE: ./rsync.sh ['uninstall' | 'install' | 'run'] ['push' | 'pull'] [local_dir] [remote_user] [remote_host] [remote_dir] [remote_ssh_port]


# === FUNCTIONS ===
# --- print and exit functions ---
function print_info()
{
	echo " -- $1, continuing..."
}

function print_warn()
{
	echo " ** $1. You may want to look into this, continuing..."
}

function force_exit()
{
	echo " !! $2, exiting..."
	echo " !! USAGE: $0 ['uninstall' | 'install' | 'run'] ['push' | 'pull'] [local_dir] [remote_user] [remote_host] [remote_dir] [remote_ssh_port]"
	cleanup # cleanup rsync log files
	exit $1
}

function safe_exit()
{
	echo " -- Safely exiting..."
	cleanup # cleanup rsync log files
	exit 0
}

# --- helper functions ---
function check_dir()
{
	if [ ! -d $1 ]; then
		print_info "Creating directory: $1"

		mkdir -p $1 # if $1 doesn't exist, create it
		if [ $? -ne 0 ]; then
			force_exit 1 "Could not create $1"
		fi
	fi
}

function check_key()
{
	# make sure the local key has been created
	if [ ! -f $1 ]; then
		create_key
	fi
}

function create_key()
{
	# create key
	print_info 'Creating encryption key (this may take some time)'
	ssh-keygen -q -t rsa -b $ENCRYPTION_STRENGTH -f $LOCAL_KEY_FILE -N '' # quiet, type (rsa), encryption strength, filename, passphrase (empty)
	if [ $? -ne 0 ]; then
		uninstall # no point having the program installed with no encryption key
		force_exit 1 'Could not create encryption key'
	fi
	
	# upload key
	print_info 'Sending encryption key'
	ssh-copy-id -i $LOCAL_KEY_FILE "-p $REMOTE_SSH_PORT $REMOTE_USER@$REMOTE_HOST"
	if [ $? -ne 0 ]; then
		uninstall # no point having the program installed without the encryption key uploaded
		force_exit 1 'Could not upload encryption key'
	fi
}

function uninstall()
{
	#if [ -f $LOCAL_BIN_FILE ]; then
	#	print_info 'Uninstalling program'
	#	rm -f $LOCAL_BIN_FILE
	#	if [ $? -ne 0 ]; then
	#		print_warn "Could not remove $LOCAL_BIN_FILE"
	#	fi
	#fi
	
	if [ -f $LOCAL_CRON_FILE ]; then
		print_info 'Uninstalling cron file'
		
		crontab -u $LOCAL_USER -r # deletes user entire crontab
		if [ $? -ne 0 ]; then
			print_warn "Could not uninstall $LOCAL_USER's crontab"
		fi
		
		rm -f $LOCAL_CRON_FILE
		if [ $? -ne 0 ]; then
			print_warn "Could not remove $LOCAL_CRON_FILE"
		fi
	fi
	
	if [ -f $LOCAL_KEY_FILE ] || [ -f $LOCAL_KEY_FILE.pub ]; then
		print_info 'Uninstalling encryption keys'

		rm -f $LOCAL_KEY_FILE $LOCAL_KEY_FILE.pub
		if [ $? -ne 0 ]; then
			print_warn "Could not remove $LOCAL_KEY_FILE and/or $LOCAL_KEY_FILE.pub"
		fi
	fi
}

function cleanup()
{
	# gunzip the logfile
	if [ -f $LOCAL_LOG_FILE ]; then
		print_info 'Compressing log file'
		
		gzip -c $LOCAL_LOG_FILE > $LOCAL_LOG_FILE.gz
		if [ $? -ne 0 ]; then
			print_warn "Could not compress $LOCAL_LOG_FILE"
		fi
	fi

	# delete the original, uncompressed logfile
	if [ -f $LOCAL_LOG_FILE ]; then
		print_info 'Removing uncompressed log file'

		rm $LOCAL_LOG_FILE
		if [ $? -ne 0 ]; then
			print_warn "Could not remove $LOCAL_LOG_FILE"
		fi
	fi
}

# === VARIABLES ===
# %Y     year
# %m     month (01..12)
# %d     day of month (e.g, 01)
# %s     seconds since 1970-01-01 00:00:00 UTC
THEDATE=`date '+%Y%m%d-%s'` # 20071010-1192044000
ENCRYPTION_STRENGTH=4096 # bits in length for rsa key (1024,2048,4096,8172,10240,20480,etc)

# parameters
if [ "$1" == "install" ] || [ "$1" == "run" ]; then
	ACTION=$1 # install? uninstall? run?
	METHOD=$2 # push? pull?
	LOCAL_DIR=$3
	REMOTE_USER=$4 # ie: brett, root
	REMOTE_HOST=$5 # ie: 192.168.1.2, example.com, sub.domain.example.com
	REMOTE_DIR=$6
	REMOTE_SSH_PORT=$7 # default is 22
else # uninstall or unknown
	ACTION=$1
	REMOTE_USER=$2
	REMOTE_HOST=$3
fi

# environment
LOCAL_USER=$USER # ie: brett, root
LOCAL_HOME=$HOME # ie: /home/brett, /root

# executable
LOCAL_BIN_NAME='rsync.sh'
LOCAL_BIN_PATH=$LOCAL_HOME/bin
LOCAL_BIN_FILE=$LOCAL_BIN_PATH/$LOCAL_BIN_NAME # ie: /home/brett/bin/rsync.sh

# unique key
KEY="$REMOTE_HOST-$REMOTE_USER" # 192.168.1.2-brett, example.com-root

# cron
LOCAL_CRON_NAME="rsync-$KEY.cron"
LOCAL_CRON_PATH=$LOCAL_HOME/cron
LOCAL_CRON_FILE=$LOCAL_CRON_PATH/$LOCAL_CRON_NAME # ie: /home/brett/cron/rsync-ssh-example.com-root.cron
LOCAL_CRON_TIME='0 2 * * *' # 2am # minute, hour, day of month, month, day of week

# rsa/dsa key
LOCAL_KEY_NAME="rsync-$KEY" # using local username to avoid collisions
LOCAL_KEY_PATH=$LOCAL_HOME/.ssh
LOCAL_KEY_FILE=$LOCAL_KEY_PATH/$LOCAL_KEY_NAME # ie: /home/brett/.ssh/altonlabs-rsync-ssh

# log
LOCAL_LOG_NAME="rsync-$KEY-$THEDATE.log"
LOCAL_LOG_PATH=$LOCAL_HOME/logs
LOCAL_LOG_FILE=$LOCAL_LOG_PATH/$LOCAL_LOG_NAME # ie: /home/brett/logs/rsync-20071010-1192044000.log
LOCAL_LOG_GZ_FILE=$LOCAL_LOG_FILE.gz # ie: /home/brett/logs/rsync-20071010-1192044000.log.gz


# === LOGIC ===
# --- UPLOADING (push) / DOWNLOADING (pull) ---
if [ "$ACTION" == "run" ]; then

	# need 7 parameters to continue
	if [ $# -ne 7 ]; then
		force_exit 1 "Improper number of parameters ($#)"
	fi

	check_dir $LOCAL_LOG_PATH

	# run rsync
	# -a, --archive               archive mode; equals -rlptgoD (no -H,-A,-X)
	# -v, --verbose               increase verbosity
	# -z, --compress              compress file data during the transfer
	# -e, --rsh=COMMAND           specify the remote shell to use
	#     --delete                delete extraneous files from dest dirs
	#     --log-file=FILE         log what we're doing to the specified FILE
	
	# TODO: apperently Red Hat/Fedora/CentOS doesn't have the --log-file option in rsync, so I must add Debian/Ubuntu vs CentOS detection
	
	if [ "$METHOD" == "push" ]; then # local to remote
		rsync -avz --rsh="ssh -l $REMOTE_USER -p $REMOTE_SSH_PORT -i $LOCAL_KEY_FILE" --delete $LOCAL_DIR $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR # --log-file=$LOCAL_LOG_FILE
	elif [ "$METHOD" == "pull" ]; then # remote to local
		rsync -avz --rsh="ssh -l $REMOTE_USER -p $REMOTE_SSH_PORT -i $LOCAL_KEY_FILE" --delete $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR $LOCAL_DIR # --log-file=$LOCAL_LOG_FILE
	else
		echo " ** Incorrect method selected: $METHOD (should be 'push' or 'pull')" # print to screen
		echo " ** Incorrect method selected: $METHOD (should be 'push' or 'pull')" > $LOCAL_LOG_FILE # echo to log file
	fi

# --- INSTALLING ---
elif [ "$ACTION" == "install" ]; then

	# needs 7 parameters to continue
	if [ $# -ne 7 ]; then
		force_exit 7 "Improper number of parameters ($#)"
	fi

	check_dir $LOCAL_BIN_PATH
	check_dir $LOCAL_CRON_PATH
	check_dir $LOCAL_LOG_PATH
	check_key $LOCAL_KEY_FILE

	# install program to $LOCAL_BIN_FILE
	print_info 'Installing program'
	cp -pf $0 $LOCAL_BIN_FILE # force copy to make sure this current version is the newest
	if [ $? -ne 0 ]; then
		uninstall # if you can't install it, remove anything left behind
		force_exit 1 "Could not install program at $LOCAL_BIN_FILE"
	fi

	# create cron
	# http://en.wikipedia.org/wiki/cron#Fields
	print_info 'Creating cron file'
	echo "$LOCAL_CRON_TIME $LOCAL_BIN_FILE run $METHOD $LOCAL_DIR $REMOTE_USER $REMOTE_HOST $REMOTE_DIR $REMOTE_SSH_PORT" > $LOCAL_CRON_FILE # not checking to see if cron file already exists because we want to overwrite
	if [ $? -ne 0 ]; then
		uninstall # if you can't install it, remove anything left behind
		force_exit 1 "Could not create cron file at $LOCAL_CRON_FILE"
	fi
	
	# install cron
	print_info 'Registering cron file'
	crontab -u $LOCAL_USER $LOCAL_CRON_FILE
	if [ $? -ne 0 ]; then
		uninstall # if you can't install it, remove anything left behind
		force_exit 1 "Could not register cron file $LOCAL_CRON_FILE to $LOCAL_USER"
	fi

# --- UNINSTALLING ---
elif [ "$ACTION" == "uninstall" ]; then
	# need only 1 parameter to continue
	if [ $# -ne 3 ]; then
		force_exit 1 "Improper number of parameters ($#)"
	fi

	uninstall # call uninstall function

# --- WHOOPS ---
else
	force_exit 1 'Unknown parameter'
fi

safe_exit # everything went fine
