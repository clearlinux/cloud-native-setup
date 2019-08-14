#!/usr/bin/env Rscript
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Display details for the 'Device Under Test', for all data sets being processed.

suppressMessages(suppressWarnings(library(tidyr)))	# for gather().
library(tibble)
suppressMessages(suppressWarnings(library(plyr)))	# rbind.fill
							# So we can plot multiple graphs
library(gridExtra)					# together.
suppressMessages(suppressWarnings(library(ggpubr)))	# for ggtexttable.
suppressMessages(library(jsonlite))			# to load the data.

# A list of all the known results files we might find the information inside.
resultsfiles=c(
	"k8s-parallel.json",
	"k8s-scaling.json"
	)

data=c()
stats=c()
stats_names=c()

# For each set of results
for (currentdir in resultdirs) {
	count=1
	dirstats=c()
	for (resultsfile in resultsfiles) {
		fname=paste(inputdir, currentdir, resultsfile, sep="/")
		if ( !file.exists(fname)) {
			#warning(paste("Skipping non-existent file: ", fname))
			next
		}

		# Derive the name from the test result dirname
		datasetname=basename(currentdir)

		# Import the data
		fdata=fromJSON(fname)

		if (length(fdata$'kubectl-version') != 0 ) {
			# We have kata-runtime data
			dirstats=tibble("Client Ver"=as.character(fdata$'kubectl-version'$clientVersion$gitVersion))
			dirstats=cbind(dirstats, "Server Ver"=as.character(fdata$'kubectl-version'$serverVersion$gitVersion))
			numnodes= nrow(fdata$'kubectl-get-nodes'$items)
			dirstats=cbind(dirstats, "No. nodes"=as.character(numnodes))

			if (numnodes != 0) {
				first_node=fdata$'kubectl-get-nodes'$items[1,]
				dirstats=cbind(dirstats, "- Node0 name"=as.character(first_node$metadata$name))

				havekata=first_node$metadata$labels$'katacontainers.io/kata-runtime'
				if ( is.null(havekata) ) {
					dirstats=cbind(dirstats, "  Have Kata"=as.character('false'))
				} else {
					dirstats=cbind(dirstats, "  Have Kata"=as.character(havekata))
				}

				dirstats=cbind(dirstats, "  CPUs"=as.character(first_node$status$capacity$cpu))
				dirstats=cbind(dirstats, "  Memory"=as.character(first_node$status$capacity$memory))
				dirstats=cbind(dirstats, "  MaxPods"=as.character(first_node$status$capacity$pods))
				dirstats=cbind(dirstats, "  PodCIDR"=as.character(first_node$spec$podCIDR))

				dirstats=cbind(dirstats, "  runtime"=as.character(first_node$status$nodeInfo$containerRuntimeVersion))
				dirstats=cbind(dirstats, "  kernel"=as.character(first_node$status$nodeInfo$kernelVersion))
				dirstats=cbind(dirstats, "  kubeProxy"=as.character(first_node$status$nodeInfo$kubeProxyVersion))
				dirstats=cbind(dirstats, "  Kubelet"=as.character(first_node$status$nodeInfo$kubeletVersion))
				dirstats=cbind(dirstats, "  OS"=as.character(first_node$status$nodeInfo$osImage))
			}

			break
		}
	}

	if ( length(dirstats) == 0 ) {
		warning(paste("No valid data found for directory ", currentdir))
	}

	# use plyr rbind.fill so we can combine disparate version info frames
	stats=rbind.fill(stats, dirstats)
	stats_names=rbind(stats_names, datasetname)
}

rownames(stats) = stats_names

# Rotate the tibble so we get data dirs as the columns
spun_stats = as_tibble(cbind(What=names(stats), t(stats)))

# Build us a text table of numerical results
# Set up as left hand justify, so the node data indent renders.
tablefontsize=8
tbody.style = tbody_style(hjust=0, x=0.1, size=tablefontsize)
stats_plot = suppressWarnings(ggtexttable(data.frame(spun_stats, check.names=FALSE),
	theme=ttheme(base_size=tablefontsize, tbody.style=tbody.style),
	rows=NULL
	))

# It may seem odd doing a grid of 1x1, but it should ensure we get a uniform format and
# layout to match the other charts and tables in the report.
master_plot = grid.arrange(
	stats_plot,
	nrow=1,
	ncol=1 )

