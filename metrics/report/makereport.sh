#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Take the data found in subdirectories of the metrics 'results' directory,
# and turn them into a PDF report. Use a Dockerfile containing all the tooling
# and scripts we need to do that.

set -e

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

IMAGE="${IMAGE:-metrics-report}"
DOCKERFILE="${SCRIPT_PATH}/report_dockerfile/Dockerfile"

HOSTINPUTDIR="${SCRIPT_PATH}/../results"
RENVFILE="${HOSTINPUTDIR}/Env.R"
HOSTOUTPUTDIR="${SCRIPT_PATH}/output"

GUESTINPUTDIR="/inputdir/"
GUESTOUTPUTDIR="/outputdir/"

# If in debugging mode, we also map in the scripts dir so you can
# dynamically edit and re-load them at the R prompt
HOSTSCRIPTDIR="${SCRIPT_PATH}/report_dockerfile"
GUESTSCRIPTDIR="/scripts/"

# This function performs a docker build on the image names
# passed in, to ensure that we have the latest changes from
# the dockerfiles
build_dockerfile_image()
{
	local image="$1"
	local dockerfile_path="$2"
	local dockerfile_dir=${2%/*}

	echo "docker building $image"
	if ! docker build --label "$image" --tag "${image}" -f "$dockerfile_path" "$dockerfile_dir"; then
		die "Failed to docker build image $image"
	fi
}

# This function verifies that the dockerfile version is
# equal to the test version in order to build the image or
# just run the test
check_dockerfiles_images()
{
	local image="$1"
	local dockerfile_path="$2"

	if [ -z "$image" ] || [ -z "$dockerfile_path" ]; then
		die "Missing image or dockerfile path variable"
	fi

	# Verify that dockerfile version is equal to test version
	check_image=$(docker images "$image" -q)
	if [ -n "$check_image" ]; then
		# Check image label
		check_image_version=$(docker image inspect $image | grep -w DOCKERFILE_VERSION | head -1 | cut -d '"' -f4)
		if [ -n "$check_image_version" ]; then
			echo "$image is not updated"
			build_dockerfile_image "$image" "$dockerfile_path"
		else
			# Check dockerfile label
			dockerfile_version=$(grep DOCKERFILE_VERSION $dockerfile_path | cut -d '"' -f2)
			if [ "$dockerfile_version" != "$check_image_version" ]; then
				echo "$dockerfile_version is not equal to $check_image_version"
				build_dockerfile_image "$image" "$dockerfile_path"
			fi
		fi
	else
		build_dockerfile_image "$image" "$dockerfile_path"
	fi
}

setup() {
	echo "Checking subdirectories"
	check_subdir="$(ls -dx ${HOSTINPUTDIR}/*/ 2> /dev/null | wc -l)"
	if [ $check_subdir -eq 0 ]; then
		die "No subdirs in [${HOSTINPUTDIR}] to read results from."
	fi

	echo "Checking Dockerfile"
	check_dockerfiles_images "$IMAGE" "$DOCKERFILE"

	mkdir -p "$HOSTOUTPUTDIR" && true

	echo "inputdir=\"${GUESTINPUTDIR}\"" > ${RENVFILE}
	echo "outputdir=\"${GUESTOUTPUTDIR}\"" >> ${RENVFILE}

	# A bit of a hack to get an R syntax'd list of dirs to process
	# Also, need it as not host-side dir path - so short relative names
	resultdirs="$(cd ${HOSTINPUTDIR}; ls -dx */)"
	resultdirslist=$(echo ${resultdirs} | sed 's/ \+/", "/g')
	echo "resultdirs=c(" >> ${RENVFILE}
	echo "	\"${resultdirslist}\"" >> ${RENVFILE}
	echo ")" >> ${RENVFILE}
}

run() {
	docker run -ti --rm -v ${HOSTINPUTDIR}:${GUESTINPUTDIR} -v ${HOSTOUTPUTDIR}:${GUESTOUTPUTDIR} ${extra_volumes} ${IMAGE} ${extra_command}
	ls -la ${HOSTOUTPUTDIR}/*
}

main() {

	local OPTIND
	while getopts "d" opt;do
		case ${opt} in
		d)
			# In debug mode, run a shell instead of the default report generation
			extra_command="bash"
			extra_volumes="-v ${HOSTSCRIPTDIR}:${GUESTSCRIPTDIR}"
			;;
		esac
	done
	shift $((OPTIND-1))

	setup
	run
}

main "$@"

