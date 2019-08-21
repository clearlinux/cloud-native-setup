#!/usr/bin/env Rscript
# Copyright (c) 2018-2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Show pod scaling data - memory use, boot time, CPU utilisation.

suppressMessages(suppressWarnings(library(ggplot2)))	# ability to plot nicely.
							# So we can plot multiple graphs
library(gridExtra)					# together.
suppressMessages(suppressWarnings(library(ggpubr)))	# for ggtexttable.
suppressMessages(library(jsonlite))			# to load the data.
suppressMessages(library(scales))			# For de-science notation of axis
library(tibble)						# tibbles for tidy data

testnames=c(
	"k8s-scaling.*"
)

bootdata=c()	# Track per-launch data
nodedata=c()	# Track node status data
memstats=c()	# Statistics for memory usage
cpustats=c()	# Statistics for cpu usage
bootstats=c()	# Statistics for boot (launch) times

# iterate over every set of results (test run)
for (currentdir in resultdirs) {
	# For every results file we are interested in evaluating
	for (testname in testnames) {
		matchdir=paste(inputdir, currentdir, sep="")
		matchfile=paste(testname, '\\.json', sep="")
		files=list.files(matchdir, pattern=matchfile)
		if ( length(files) == 0 ) {
			#warning(paste("Pattern [", matchdir, "/", matchfile, "] matched nothing"))
		}

		# For every matching results file
		for (ffound in files) {
			fname=paste(inputdir, currentdir, ffound, sep="")
			if ( !file.exists(fname)) {
				warning(paste("Skipping non-existent file: ", fname))
				next
			}

			# Derive the name from the test result dirname
			datasetname=basename(currentdir)

			# Import the data
			fdata=fromJSON(fname)
			# De-nest the test name specific data
			shortname=substr(ffound, 1, nchar(ffound)-nchar(".json"))
			fdata=fdata[[shortname]]
			testname=datasetname

			# Most of the data we are looking for comes in BootResults, so pick it out to make
			# referencing easier
			br=fdata$BootResults

			# The launched pods is a list of data frames when imported. It is much nicer
			# for us to work with it as a single data frame, so convert it...
			lp=do.call("rbind", br$launched_pods)

			########################################################
			#### Now extract all the pod launch boot data items ####
			########################################################
			local_bootdata=tibble(launch_time=br$launch_time$Result)
			local_bootdata=cbind(local_bootdata, n_pods=br$n_pods$Result)
			local_bootdata=cbind(local_bootdata, node=lp$node)
			local_bootdata=cbind(local_bootdata, testname=rep(testname, length(local_bootdata$node)))


			########################################################
			#### Now extract all node performance information ######
			########################################################
			nu=br$node_util

			# We need to associate a pod count with each result, but you
			# get one result per-node, and the JSON does not carry the pod
			# count in that table. Walk the node util structure, assigning the
			# n_pods value from the boot results over to the list of node util
			# entries associated with it - creating a new 'n_pods' field in the
			# node util dataframe.
			for (n in seq(length(br$n_pods$Result))) {
				nu[[n]]$n_pods = br$n_pods$Result[[n]]
			}

			# node_util is a list of nested data frames. I'm sure there is some better R'ish
			# way of extracting this data maybe with dplyr, map, select or melt, but I can't
			# work it out right now, and at least this is semi-readable...
			#
			# Basically, we are de-listing and flattening the lists of dataframes into a
			# singly 'tidy' dataframe...
			nodes=do.call("rbind", lapply(nu, "[", "node"))
			noschedule=do.call("rbind", lapply(nu, "[", "noschedule"))
			n_pods=do.call("rbind", lapply(nu, "[", "n_pods"))
			idle=lapply(nu, "[", "cpu_idle")
			idle_df=do.call("rbind", lapply(idle, "[[", "cpu_idle"))
			free=lapply(nu, "[", "mem_free")
			free_df=do.call("rbind", lapply(free, "[[", "mem_free"))
			used=lapply(nu, "[", "mem_used")
			used_df=do.call("rbind", lapply(used, "[[", "mem_used"))

			# and build our rows
			local_nodedata=tibble(node=nodes$node)
			local_nodedata=cbind(local_nodedata, n_pods=n_pods)
			local_nodedata=cbind(local_nodedata, noschedule=noschedule)
			local_nodedata=cbind(local_nodedata, idle=idle_df$Result)
			local_nodedata=cbind(local_nodedata, mem_free=free_df$Result)
			local_nodedata=cbind(local_nodedata, mem_used=used_df$Result)
			local_nodedata=cbind(local_nodedata, testname=rep(testname, length(local_nodedata$node)))

			# Now Calculate some stats. This gets more complicated as we may have n-nodes,
			# and we want to show a 'pod average', so we try to assess for all nodes. If
			# we have different 'size' nodes in a cluster, that could throw out the result,
			# but the only other option would be to try and show every node separately in the
			# table.

			# Get a list of all the nodes
			nodes=unique(local_nodedata$node)

			memtotal=0
			cputotal=0
			# Calculate per-node totals, and tot them up to a global total.
			for (n in nodes) {
				# Make a frame with just that nodes data in
				thisnode=subset(local_nodedata, node %in% c(n))
				memtotal = memtotal + thisnode[nrow(thisnode),]$mem_used
				cpuused = thisnode[1,]$idle - thisnode[nrow(thisnode),]$idle
				cputotal = cputotal + cpuused
			}

			# We get data in Kb, but want the graphs in Gb.
			memtotal = memtotal / (1024*1024)
			gb_per_pod = memtotal/fdata$Config$NUM_PODS
			pod_per_gb = 1/gb_per_pod

			# Memory usage stats.
			local_mems = c(
				"Test"=testname,
				"n"=fdata$Config$NUM_PODS,
				"Tot_Gb"=round(memtotal, 3),
				"avg_Gb"=round(gb_per_pod, 4),
				"n_per_Gb"=round(pod_per_gb, 2) 
			)
			memstats=rbind(memstats, local_mems)

			# cpu usage stats
			local_cpus = c(
				"Test"=testname,
				"n"=fdata$Config$NUM_PODS,
				"Tot_CPU"=round(cputotal, 3),
				"avg_CPU"=round(cputotal/fdata$Config$NUM_PODS, 4)
			)
			cpustats=rbind(cpustats, local_cpus)

			# launch (boot) stats
			local_boots = c(
				"Test"=testname,
				"n"=fdata$Config$NUM_PODS,
				"median"=median(na.omit(local_bootdata)$launch_time)/1000,
				"min"=min(na.omit(local_bootdata)$launch_time)/1000,
				"max"=max(na.omit(local_bootdata)$launch_time)/1000,
				"sd"=round(sd(na.omit(local_bootdata)$launch_time)/1000, 4)
				)

			bootstats=rbind(bootstats, local_boots)
		}

		# And collect up our rows into our global table of all results
		# These two tables *should* be the source of all the data we need to
		# process and plot (apart from the stats....)
		bootdata=rbind(bootdata, local_bootdata, make.row.names=FALSE)
		nodedata=rbind(nodedata, local_nodedata, make.row.names=FALSE)
	}
}

# It's nice to show the graphs in Gb, at least for any decent sized test
# run, so make a new column with that pre-divided data in it for us to use.
nodedata$mem_free_gb = nodedata$mem_free/(1024*1024)
nodedata$mem_used_gb = nodedata$mem_used/(1024*1024)

# The labels get messed up by us using an 'if' in the aes() - correct it by
# using the same 'if' to assign what we really want to use for the labels.
colour_label=(if(length(resultdirs)> 1) "testname" else "node")


########## Output memory page ##############
mem_stats_plot = suppressWarnings(ggtexttable(data.frame(memstats),
	theme=ttheme(base_size=10),
	rows=NULL
	))

mem_line_plot <- ggplot(data=nodedata, aes(n_pods,
		mem_free_gb,
		colour=(if (length(resultdirs) > 1) testname else node),
		group=interaction(testname, node))) +
	labs(colour=colour_label) +
	geom_line(alpha=0.2) +
	geom_point(aes(shape=node), alpha=0.3, size=0.5) +
	xlab("pods") +
	ylab("System Avail (Gb)") +
	scale_y_continuous(labels=comma) +
	ggtitle("System Memory free") +
	theme(axis.text.x=element_text(angle=90))

page1 = grid.arrange(
	mem_line_plot,
	mem_stats_plot,
	ncol=1
	)

# pagebreak, as the graphs overflow the page otherwise
cat("\n\n\\pagebreak\n")

########## Output cpu page ##############
cpu_stats_plot = suppressWarnings(ggtexttable(data.frame(cpustats),
	theme=ttheme(base_size=10),
	rows=NULL
	))

cpu_line_plot <- ggplot(data=nodedata, aes(n_pods,
		idle,
		colour=(if (length(resultdirs) > 1) testname else node),
		group=interaction(testname, node))) +
	labs(colour=colour_label) +
	geom_line(alpha=0.2) +
	geom_point(aes(shape=node), alpha=0.3, size=0.5) +
	xlab("pods") +
	ylab("System CPU Idle (%)") +
	ggtitle("System CPU usage") +
	theme(axis.text.x=element_text(angle=90))

page2 = grid.arrange(
	cpu_line_plot,
	cpu_stats_plot,
	ncol=1
	)

# pagebreak, as the graphs overflow the page otherwise
cat("\n\n\\pagebreak\n")

########## Output boot page ##############
boot_stats_plot = suppressWarnings(ggtexttable(data.frame(bootstats),
	theme=ttheme(base_size=10),
	rows=NULL
	))

boot_line_plot <- ggplot() +
	geom_line( data=bootdata, aes(n_pods, launch_time, colour=testname, group=testname), alpha=0.2) +
	geom_point( data=bootdata, aes(n_pods, launch_time, colour=interaction(testname, node), group=testname), alpha=0.6, size=0.6, stroke=0, shape=16) +
	xlab("pods") +
	ylab("Boot time (s)") +
	ggtitle("Pod boot time") +
	theme(axis.text.x=element_text(angle=90))

page3 = grid.arrange(
	boot_line_plot,
	boot_stats_plot,
	ncol=1
	)

