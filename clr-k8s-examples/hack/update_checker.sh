#!/usr/bin/env bash

###
# update_checker.sh
# Parses create_stack.sh for urls and versions
# Curls urls for latest version and reports the comparison
##

# first argument is path to create_stach.sh
COMPONENT_FILE="${1:-$create_stack.sh}"
# set CLRK8S_DEBUG=1 for debug output
DEBUG=${CLRK8S_DEBUG:-0}
# set CLRK8S_NO_COLOR=1 for no colors
NO_COLOR=${CLRK8S_NO_COLOR:-""}
# set CLRK8S_ALL=1 for all results, not just changed
ALL=${CLRK8S_ALL:-""}
# add components to skip (not check)
# - canal doesn't use git repo tags for revisions
declare -a COMPONENT_SKIP=( CANAL )

# internal vars
declare -A COMPONENT_VER
declare -A COMPONENT_URL
LATEST_URL=""

# usage prints help and exit
function usage(){
	echo "Compare default component versions to latest release"
	echo "usage: update_checker.sh <path to create_stack.sh>"
	exit 0
}
# log echoes to stdout
function log(){
	echo "$1"
}
# debug echoes to stdout if debug is enabled
function debug(){
	if [[ "${DEBUG}" -ne 0 ]]; then
	  echo "$1"
	fi
}
# extract_component_data scans file for component versions and urls and add them to maps
function extract_component_data(){
	file=${1:-$COMPONENT_FILE}
	name=""
	version=""
	url=""
	while read -r line
	do
		# versions
	  if [[ $line =~ "_VER=" ]]; then
			debug "Found component version $line"
			name=${line%%_*}
			if [[ "$COMPONENT_SKIP" =~ (^|[[:space:]])"$name"($|[[:space:]]) ]]; then
				debug "Skipping component $name"
				continue
			fi
			versions=${line#*=}
			if [[ $versions =~ ":-" ]]; then
				version=${line#*:-}
			fi
			# cleanup value
			version=${version%\}}
			version=${version%\}\"}
			if [[ -n "$name" && ${COMPONENT_VER[$name]} == "" ]]; then
				debug "Adding component $name=$version to COMPONENT_VER"
				COMPONENT_VER[$name]=$version
	  	fi
	  fi

	  # urls
	  if [[ $line =~ "_URL=" ]]; then
	    debug "Found component URL $line"
			name=${line%%_*}
			if [[ $COMPONENT_SKIP =~ (^|[[:space:]])"$name"($|[[:space:]]) ]]; then
				debug "Skipping component $name"
				continue
			fi
			urls=${line#*=}

			if [[ $urls =~ ":-" ]]; then
				urls=${line#*:-}
			fi
			# cleanup value
			url=${urls%\"}
			url=${url#\"}
			if [[ -n "$name" && ${COMPONENT_URL[$name]} == "" ]]; then
				debug "Adding component $name=$url to COMPONENT_URL"
				COMPONENT_URL[$name]=$url
	  	fi
	  fi

	done < $file

}
# resolve_latest_url extracts the real release/latest url from a repo url
function resolve_latest_url(){
	repo=$1
	url=${repo%.git*}/releases/latest
	LATEST_URL=$(curl -Ls -o /dev/null -w %{url_effective} $url)
	if [[ "$?" -gt 0 ]]; then
		echo "curl error, exiting."
		exit 1
	fi
}
# function_exists checks if a function exists
function function_exists() {
    declare -f -F "$1" > /dev/null
    return $?
}
function report(){
	if [[ -z $NO_COLOR ]]; then
		BOLD="\e[1m\e[33m"
		BOLD_OFF="\e[0m"
  fi
  mode="changed"
  out=""
  if [[ -n "$1" ]]; then
  	mode="all"
  fi
	out+="\n"
	out+="Components ($mode)\n"
	out+="--------------------------\n"
	echo -e $out
	out="NAME CURRENT LATEST\n"
	# loop thru each url, get latest version and report
	for k in "${!COMPONENT_URL[@]}";
	do
		name=$k
		resolve_latest_url "${COMPONENT_URL[$k]}"
		latest_url="$LATEST_URL"
		latest_ver="${latest_url#*tag/}"
		current_ver="${COMPONENT_VER[$name]}"
		if [[ "${current_ver}" != "${latest_ver}" ]]; then
			out+="$name $current_ver $BOLD $latest_ver $BOLD_OFF\n";
		fi
		if [[ "${current_ver}" == "${latest_ver}" && -n $ALL ]]; then
			out+="$name $current_ver $latest_ver\n";
		fi
	done;
	echo -e "${out}" | column -t
	if [[ "${#COMPONENT_SKIP[@]}" -gt 0 ]]; then
		echo "---"
		echo "WARNING: Skipped comparisions for the following components:"
		for s in "${!COMPONENT_SKIP[@]}"
		do
			echo "${COMPONENT_SKIP[$s]}"
		done
	fi
}
###
# Main
##

# print help if no args
if [[ "$#" -eq 0 ]]; then
	usage
fi

# get the versions
extract_component_data "$1"
# output
report "${ALL}"



