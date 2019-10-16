#!/usr/bin/env Rscript
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Display details for the 'Nodes within Kubernetes cluster'.

suppressMessages(suppressWarnings(library(tidyr)))      # for gather().
library(tibble)
suppressMessages(suppressWarnings(library(plyr)))       # rbind.fill
                                                        # So we can plot multiple graphs
library(gridExtra)                                      # together.
suppressMessages(suppressWarnings(library(ggpubr)))     # for ggtexttable.
suppressMessages(library(jsonlite))                     # to load the data.

# A list of all the known results files we might find the information inside.
resultsfiles=c(
	       "k8s-scaling.json"
	       )

stats=c()
stats_names=c()
max_char_name_node=18

# list for each dirstats
dirstats_list=list()
j=1

# For each set of results
for (currentdir in resultdirs) {
	dirstats=c()
	for (resultsfile in resultsfiles) {
		fname=paste(inputdir, currentdir, resultsfile, sep="/")
		if ( !file.exists(fname)) {
			next
		}

		# Derive the name from the test result dirname
		datasetname=basename(currentdir)

		# Import the data
		fdata=fromJSON(fname)

		if (length(fdata$'kubectl-version') != 0 ) {
			numnodes= nrow(fdata$'kubectl-get-nodes'$items)
			for (i in 1:numnodes) {
				node_i=fdata$'kubectl-get-nodes'$items[i,]
				node_info=fdata$'socketsPerNode'[i,]

				# Substring node name so it fits properly into final table
				node_name=node_i$metadata$name
				if ( nchar(node_name) >= max_char_name_node) {
					dirstats=tibble("Node \nname"=as.character(substring(node_name, 1, max_char_name_node)))
				} else {
					dirstats=tibble("Node \nname"=as.character(node_name))
				}

				dirstats=cbind(dirstats, "CPUs"=as.character(node_i$status$capacity$cpu))
				dirstats=cbind(dirstats, "Memory"=as.character(node_i$status$capacity$memory))
				dirstats=cbind(dirstats, "Max \nPods"=as.character(node_i$status$capacity$pods))
				dirstats=cbind(dirstats, "Count \nsockets"=as.character(node_info$num_sockets))
				dirstats=cbind(dirstats, "Have \nhypervisor"=as.character(node_info$hypervisor))

				dirstats=cbind(dirstats, "kernel"=as.character(node_i$status$nodeInfo$kernelVersion))
				dirstats=cbind(dirstats, "OS"=as.character(node_i$status$nodeInfo$osImage))
				dirstats=cbind(dirstats, "Test"=as.character(datasetname))

				dirstats_list[[j]]=dirstats
				j=j+1
			}
			complete_data = do.call(rbind, dirstats_list)
		}
	}

	if ( length(complete_data) == 0 ) {
		warning(paste("No valid data found for directory ", currentdir))
	}

	# use plyr rbind.fill so we can combine disparate version info frames
	stats=rbind.fill(stats, complete_data)
	stats_names=rbind(stats_names, datasetname)
}
# Build us a text table of numerical results
# Set up as left hand justify, so the node data indent renders.
tablefontsize=8
tbody.style = tbody_style(hjust=0, x=0.1, size=tablefontsize)
stats_plot = suppressWarnings(ggtexttable(data.frame(complete_data, check.names=FALSE),
					  theme=ttheme(base_size=tablefontsize, tbody.style=tbody.style),
					  rows=NULL))

# It may seem odd doing a grid of 1x1, but it should ensure we get a uniform format and
# layout to match the other charts and tables in the report.
master_plot = grid.arrange(stats_plot,
			   nrow=1,
			   ncol=1 )
