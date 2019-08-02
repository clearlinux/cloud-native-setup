#!/usr/bin/env Rscript
# Copyright (c) 2018-2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Show system memory reduction, and hence container 'density', by analysing the
# scaling footprint data results and the 'system free' memory.

suppressMessages(suppressWarnings(library(ggplot2)))	# ability to plot nicely.
							# So we can plot multiple graphs
library(gridExtra)					# together.
suppressMessages(suppressWarnings(library(ggpubr)))	# for ggtexttable.
suppressMessages(library(jsonlite))			# to load the data.
suppressMessages(library(scales))			# For de-science notation of axis

testnames=c(
	"k8s-scaling.*"
)

data=c()
fndata=c()
stats=c()
rstats=c()
rstats_names=c()
cstats=c()
cstats_names=c()

skip_points=0	# Shall we draw the points as well as lines on the graphs.

# FIXME GRAHAM - bomb if there are no source dirs?!

for (currentdir in resultdirs) {
	count=1
	dirstats=c()
	for (testname in testnames) {
		matchdir=paste(inputdir, currentdir, sep="")
		matchfile=paste(testname, '\\.json', sep="")
		files=list.files(matchdir, pattern=matchfile)
		if ( length(files) == 0 ) {
			#warning(paste("Pattern [", matchdir, "/", matchfile, "] matched nothing"))
		}
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

			cdata=data.frame(boot_time=as.numeric(fdata$BootResults$launch_time$Result)/1000)

			# format the utilization data
			udata=data.frame(nodename=fdata$BootResults$node_util)
			for (i in seq(length(cdata[, "boot_time"]))) {
				if (i == 1) {
					# first iteration provide column name for c1
					c1=cbind(node=udata$nodename.node)
					c2=cbind(udata$nodename.noschedule)
					c3=cbind(udata$nodename.cpu_idle$Result)
					c4=cbind(udata$nodename.mem_free$Result)/(1024*1024)
					c5=cbind(rep(i, length(udata$nodename.node)))
					c6=cbind(rep(testname, length(udata$nodename.node)))
					# declare formatted utility data
					fudata=cbind(c1,c2,c3,c4,c5,c6)
				}
				else {
					# shift to 0 based indexing
					index=i-1
					sindex=(index*4)+1
					eindex=sindex+3
					# grab 3 columns for next row bind
					row=cbind(udata[,sindex:eindex])
					c1=cbind(node=row[,1])
					c2=cbind(row[,2])
					c3=cbind(row[,3]$Result)
					c4=cbind(row[,4]$Result)/(1024*1024)
					c5=cbind(rep(i, length(udata$nodename.node)))
					c6=cbind(rep(testname, length(udata$nodename.node)))
					# create the new row (which is actually the number of nodes of rows)
					frow=cbind(c1,c2,c3,c4,c5,c6)
					fudata=rbind(fudata,frow)
				}
			}
			colnames(fudata)=c("node", "noschedule", "cpu_idle", "mem_free", "pod", "testname")
			# fudata is considered a vector for some reason so converting it to a data.frame
			fudata=as.data.frame(fudata)
			# get unique node names
			nodes=unique(fudata$node)

			for (nodename in nodes) {
				c1=cbind(subset(fudata,node==nodename)["noschedule"])
				colnames(c1)=paste(nodename,"_noschedule", sep="")
				cdata=cbind(cdata, c1)

				c2=cbind(subset(fudata,node==nodename)["mem_free"])
				# extra work to name the column from a variable
				colnames(c2)=paste(nodename,"_avail_gb", sep="")
				cdata=cbind(cdata, c2)

				c3=cbind(subset(fudata,node==nodename)["cpu_idle"])
				colnames(c3)=paste(nodename,"_cpu_idle", sep="")
				cdata=cbind(cdata, c3)
			}

			# convert ms to seconds
			# FIXME - we should seq from 0 index
			if (length(cdata[, "boot_time"]) > 20) {
				skip_points=1
			}

			cdata=cbind(cdata, count=seq_len(length(cdata[, "boot_time"])))
			cdata=cbind(cdata, testname=rep(testname, length(cdata[, "boot_time"]) ))
			cdata=cbind(cdata, dataset=rep(datasetname, length(cdata[, "boot_time"]) ))

			# Gather our statistics
			# '-1' containers, as the first entry should be a data capture of before
			# the first container was run.
			# FIXME - once the test starts to store a stats baseline in slot 0, then
			# we should re-enable the '-1'
			#sdata=data.frame(num_containers=length(cdata[, "avail_gb"])-1)
			sdata=data.frame(num_containers=length(cdata[, "boot_time"]))
			sudata=c()
			# first (which should be 0-containers)
			for (nodename in nodes) {
				node_noschedule=paste(nodename, "_noschedule", sep="")
				# if workloads are not scheduled on this node, don't include it in the calculations below
				if(cdata[, node_noschedule][1] == "true") {
					next
				}
				node_avail_gb=paste(nodename, "_avail_gb", sep="")
				# Work out memory reduction by subtracting last (most consumed) from
				srdata=cbind(mem_consumed=as.numeric(as.character(cdata[, node_avail_gb][1])) -
							 as.numeric(as.character(cdata[, node_avail_gb][length(cdata[, node_avail_gb])])))
				
				node_cpu_idle=paste(nodename, "_cpu_idle", sep="")
				srdata=cbind(srdata, cpu_consumed=as.numeric(as.character(cdata[, node_cpu_idle][1])) -
							 as.numeric(as.character(cdata[, node_cpu_idle][length(cdata[, node_cpu_idle])])))
				sudata=rbind(sudata, srdata)
			}
			sdata=cbind(sdata, mem_consumed=sum(sudata[, "mem_consumed"]))
			sdata=cbind(sdata, cpu_consumed=sum(sudata[, "cpu_consumed"]))
			sdata=cbind(sdata, boot_time=cdata[, "boot_time"][length(cdata[, "boot_time"])])
			sdata=cbind(sdata, avg_gb_per_c=sdata$mem_consumed / sdata$num_containers)
			sdata=cbind(sdata, runtime=testname)

			# Store away as a single set
			data=rbind(data, cdata)
			fndata=rbind(fndata, fudata)
			stats=rbind(stats, sdata)

			ms = c(
				"Test"=testname,
				"n"=sdata$num_containers,
				"size"=round((sdata$mem_consumed), 3),
				"gb/n"=round(sdata$avg_gb_per_c, digits=4),
				"n/Gb"= round(1 / sdata$avg_gb_per_c, digits=2)
			)

			cs = c(
				"Test"=testname,
				"n"=sdata$num_containers,
				"cpu"=round(sdata$cpu_consumed, digits=3),
				"cpu/n"=round((sdata$cpu_consumed / sdata$num_containers), digits=4)
			)

			rstats=rbind(rstats, ms)
			cstats=rbind(cstats, cs)
			count = count + 1
		}
	}
}

#FIXME - if we end up with no data here, we should probably abort cleanly, or we
# end up spewing errors for trying to access empty arrays etc.

# Set up the text table headers
colnames(rstats)=c("Test", "n", "Tot_Gb", "avg_Gb", "n_per_Gb")
colnames(cstats)=c("Test", "n", "Tot_CPU", "avg_CPU")

# Build us a text table of numerical results
mem_stats_plot = suppressWarnings(ggtexttable(data.frame(rstats),
	theme=ttheme(base_size=10),
	rows=NULL
	))

# plot how samples varied over	'time'
mem_line_plot <- ggplot(data=fndata, aes(as.numeric(as.character(pod)),
		as.numeric(as.character(mem_free)),
		colour=testname, group=interaction(testname, node))) +
	geom_line(alpha=0.2) +
	xlab("Pods") +
	ylab("System Avail (Gb)") +
	scale_y_continuous(labels=comma) +
	ggtitle("System Memory free") +
	#ylim(0, NA) + # For big machines, better to not 0-index
	theme(axis.text.x=element_text(angle=90))

# If we only have relatively few samples, add points to the plot. Otherwise, skip as
# the plot becomes far too noisy
if ( skip_points == 0 ) {
	mem_line_plot = mem_line_plot + geom_point(aes(shape=node), alpha=0.3)
}

cpu_stats_plot = suppressWarnings(ggtexttable(data.frame(cstats), theme=ttheme(base_size=10), rows=NULL))

# plot how samples varied over 'time'
cpu_line_plot <- ggplot(data=fndata, aes(as.numeric(as.character(pod)),
		as.numeric(as.character(cpu_idle)),
		colour=testname, group=interaction(testname, node))) +
	geom_line(alpha=0.2) +
	xlab("Pods") +
	ylab("System CPU Idle (%)") +
	ggtitle("System CPU usage") +
	#ylim(0, NA) + # For big machines, better to not 0-index
	theme(axis.text.x=element_text(angle=90))

if ( skip_points == 0 ) {
	cpu_line_plot = cpu_line_plot + geom_point(aes(shape=node), alpha=0.3)
}

# Show how boot time changed
boot_line_plot <- ggplot() +
	geom_line( data=data, aes(count, boot_time, colour=testname, group=dataset), alpha=0.2) +
	geom_smooth( data=data, aes(count, boot_time, colour=testname, group=dataset), se=FALSE, method="loess", size=0.3) +
	xlab("pods") +
	ylab("Boot time (s)") +
	ggtitle("Pod boot time") +
	#ylim(0, NA) + # For big machines, better to not 0-index
	theme(axis.text.x=element_text(angle=90))

if ( skip_points == 0 ) {
	boot_line_plot = boot_line_plot + geom_point( data=data, aes(count, boot_time, colour=testname, group=dataset), alpha=0.3)
}

mem_text <- paste("Footprint density statistics")
mem_text.p <- ggparagraph(text=mem_text, face="italic", size="10", color="black")

cpu_text <- paste("System CPU consumption statistics")
cpu_text.p <- ggparagraph(text=cpu_text, face="italic", size="10", color="black")

# See https://www.r-bloggers.com/ggplot2-easy-way-to-mix-multiple-graphs-on-the-same-page/ for
# excellent examples
master_plot = grid.arrange(
	mem_line_plot,
	cpu_line_plot,
	mem_stats_plot,
	mem_text.p,
	cpu_stats_plot,
	cpu_text.p,
	boot_line_plot,
	nrow=7,
	heights=c(1.5, 1.5, 0.8, 0.1, 0.8, 0.1, 1.2) )

