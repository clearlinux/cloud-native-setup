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
pndata=c()
stats=c()
rstats=c()
rstats_names=c()
cstats=c()
cstats_names=c()

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
			cdata=cbind(cdata, num_pods=as.numeric(fdata$BootResults$n_pods$Result))

			# Gather up each 'column' from the dataframe - one per run instance.
			# The length(node) parts are as each entry has an n-node array of
			# results, so each iteration can create more than one new row in the
			# final table.
			fudata=c()
			furoot=fdata$BootResults
			for (n in seq(length(furoot$n_pods$Result))) {
				num_pods=furoot$n_pods$Result[[n]]
				u=furoot$node_util[[n]]
				# first iteration provide column name for c1
				c1=cbind(node=u$node)
				c2=cbind(noschedule=u$noschedule)
				c3=cbind(cpu_idle=u$cpu_idle$Result)
				c4=cbind(mem_free=u$mem_free$Result)/(1024*1024)
				# using index to make chart start with 0 rather than 1
				c5=cbind(pod=rep(num_pods, length(u$node)))
				c6=cbind(testname=rep(testname, length(u$node)))
				# declare formatted utility data
				row=cbind(c1,c2,c3,c4,c5,c6)
				fudata=rbind(fudata,row)
			}

			# Converting the vector to a data.frame.
			# We could probably do this whole sequence more nicely if we use tibbles.
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

			# format the pod data from 2 nested columns in a series
			# of index specific columns to just 2 columns
			# omitting the first row as it is the baseline and contains
			# NA values for launched pods as there were none. If we don't
			# omit the first row, this will throw a warning, but notice that it
			# makes the index funky below
			pdata=data.frame(fdata$BootResults$launched_pods[-1])
			pudata=c()
			# pdata is 1 row shorter than cdata, hence the subtract 1
			for (i in seq(length(cdata[, "boot_time"]) - 1)) {
				# using i+1 rather than i to account for the missing row when indexing in to fdata
				num_pods=fdata$BootResults$n_pods$Result[i+1]
				# shift to 0 based indexing for pdata, so we can iterate through the generated named columns
				index=i-1
				sindex=(index*2)+1
				eindex=sindex+1
				row=cbind(pdata[,sindex:eindex])
				c1=cbind(podname=row[,1])
				c2=cbind(node=row[,2])
				c3=cbind(count=rep(num_pods, length(pdata$pod_name)))
				# using i+1 rather than i to account for the missing row when indexing in to cdata
				c4=cbind(boot_time=rep(cdata[, "boot_time"][i+1],length(pdata$pod_name)))
				c5=cbind(dataset=rep(testname, length(pdata$pod_name)))
				prow=cbind(c1,c2,c3,c4,c5)
				pudata=rbind(pudata,prow)
			}
			# pndata is considered a vector for some reason so converting it to a data.frame
			pudata=as.data.frame(pudata)
			pudata$count=as.numeric(as.character(pudata$count))
			pudata$boot_time=as.numeric(as.character(pudata$boot_time))
			
			# using 0 based index rather than starting with 1
			cdata=cbind(cdata, testname=rep(testname, length(cdata[, "boot_time"]) ))
			cdata=cbind(cdata, dataset=rep(datasetname, length(cdata[, "boot_time"]) ))

			# Gather our statistics
			# '-1' containers, as the first entry should be a data capture of before
			# the first container was run.
			sdata=data.frame(num_pods=as.numeric(as.character(cdata[, "num_pods"][length(cdata[, "num_pods"])])))
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

			# now that we have sudata, perform the calculations
			total_pods=as.numeric(as.character(cdata[, "num_pods"][length(cdata[, "num_pods"])]))
			sdata=cbind(sdata, mem_consumed=sum(sudata[, "mem_consumed"]))
			sdata=cbind(sdata, cpu_consumed=sum(sudata[, "cpu_consumed"]))
			sdata=cbind(sdata, boot_time=cdata[, "boot_time"][length(cdata[, "boot_time"])])
			sdata=cbind(sdata, avg_gb_per_c=sdata$mem_consumed / total_pods)
			sdata=cbind(sdata, runtime=testname)

			# Store away as a single set
			data=rbind(data, cdata)
			fndata=rbind(fndata, fudata)
			pndata=rbind(pndata, pudata)
			stats=rbind(stats, sdata)

			ms = c(
				"Test"=testname,
				"n"=total_pods,
				"size"=round((sdata$mem_consumed), 3),
				"gb/n"=round(sdata$avg_gb_per_c, digits=4),
				"n/Gb"= round(1 / sdata$avg_gb_per_c, digits=2)
			)

			cs = c(
				"Test"=testname,
				"n"=total_pods,
				"cpu"=round(sdata$cpu_consumed, digits=3),
				"cpu/n"=round((sdata$cpu_consumed / num_pods), digits=4)
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

num_test_runs=length(unique(fndata$testname))
colour_label=(if(num_test_runs > 1) "testname" else "node")

# Build us a text table of numerical results
mem_stats_plot = suppressWarnings(ggtexttable(data.frame(rstats),
	theme=ttheme(base_size=10),
	rows=NULL
	))

# plot how samples varied over 'time'
mem_line_plot <- ggplot(data=fndata, aes(as.numeric(as.character(pod)),
		as.numeric(as.character(mem_free)),
		colour=(if (num_test_runs > 1) testname else node),
		group=interaction(testname, node))) +
	labs(colour=colour_label) +
	geom_line(alpha=0.2) +
	geom_point(aes(shape=node), alpha=0.3, size=0.5) +
	xlab("pods") +
	ylab("System Avail (Gb)") +
	scale_y_continuous(labels=comma) +
	ggtitle("System Memory free") +
	#ylim(0, NA) + # For big machines, better to not 0-index
	theme(axis.text.x=element_text(angle=90))

cpu_stats_plot = suppressWarnings(ggtexttable(data.frame(cstats), theme=ttheme(base_size=10), rows=NULL))

# plot how samples varied over 'time'
cpu_line_plot <- ggplot(data=fndata, aes(as.numeric(as.character(pod)),
		as.numeric(as.character(cpu_idle)),
		colour=(if (num_test_runs > 1) testname else node),
		group=interaction(testname, node))) +
	labs(colour=colour_label) +
	geom_line(alpha=0.2) +
	geom_point(aes(shape=node), alpha=0.3, size=0.5) +
	xlab("pods") +
	ylab("System CPU Idle (%)") +
	ggtitle("System CPU usage") +
	#ylim(0, NA) + # For big machines, better to not 0-index
	theme(axis.text.x=element_text(angle=90))

# Show how boot time changed
boot_line_plot <- ggplot() +
	geom_line( data=data, aes(num_pods, boot_time, colour=testname, group=dataset), alpha=0.2) +
	geom_point( data=pndata, aes(count, boot_time, colour=interaction(dataset, node), group=dataset), alpha=0.6, size=0.6, stroke=0, shape=16) +
	xlab("pods") +
	ylab("Boot time (s)") +
	ggtitle("Pod boot time") +
	#ylim(0, NA) + # For big machines, better to not 0-index
	theme(axis.text.x=element_text(angle=90))

mem_text <- paste("Footprint density statistics")
mem_text.p <- ggparagraph(text=mem_text, face="italic", size="10", color="black")

cpu_text <- paste("System CPU consumption statistics")
cpu_text.p <- ggparagraph(text=cpu_text, face="italic", size="10", color="black")

# See https://www.r-bloggers.com/ggplot2-easy-way-to-mix-multiple-graphs-on-the-same-page/ for
# excellent examples
master_plot = grid.arrange(
	mem_line_plot,
	mem_stats_plot,
	cpu_line_plot,
	cpu_stats_plot,
	boot_line_plot,
	heights=c(1.5, 0.5, 1.5, 0.5, 1.5))

