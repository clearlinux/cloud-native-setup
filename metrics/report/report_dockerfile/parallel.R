#!/usr/bin/env Rscript
# Copyright (c) 2018-2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Show effects of parallel container launch on boot and deletion times by
# launching and killing off a deployment whilst ramping the number of pods requested.

suppressMessages(suppressWarnings(library(ggplot2)))	# ability to plot nicely.
							# So we can plot multiple graphs
library(gridExtra)					# together.
suppressMessages(suppressWarnings(library(ggpubr)))	# for ggtexttable.
suppressMessages(library(jsonlite))			# to load the data.
suppressMessages(library(scales))			# For de-science notation of axis

testnames=c(
	"k8s-parallel*"
)

data=c()
stats=c()
rstats=c()
rstats_names=c()
cstats=c()
cstats_names=c()

skip_points=0	# Should we draw the points as well as lines on the graphs.

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

			# convert ms to seconds
			cdata=data.frame(boot_time=as.numeric(fdata$BootResults$launch_time$Result)/1000)
			cdata=cbind(cdata, delete_time=as.numeric(fdata$BootResults$delete_time$Result)/1000)

			# If we have more than 20 items to draw, then do not draw the points on
			# the graphs, as they are then too noisy to read.
			if (length(cdata[, "boot_time"]) > 20) {
				skip_points=1
			}

			cdata=cbind(cdata, count=seq_len(length(cdata[, "boot_time"])))
			cdata=cbind(cdata, testname=rep(testname, length(cdata[, "boot_time"]) ))
			cdata=cbind(cdata, dataset=rep(datasetname, length(cdata[, "boot_time"]) ))

			# Store away as a single set
			data=rbind(data, cdata)

			count = count + 1
		}
	}
}

# Show how boot time changed
boot_line_plot <- ggplot() +
	geom_line( data=data, aes(count, boot_time, colour=testname, group=dataset), alpha=0.2) +
	geom_smooth( data=data, aes(count, boot_time, colour=testname, group=dataset), se=FALSE, method="loess", size=0.3) +
	xlab("parallel pods") +
	ylab("Boot time (s)") +
	ggtitle("Pod boot time (detail)") +
	#ylim(0, NA) + # For big machines, better to not 0-index
	theme(axis.text.x=element_text(angle=90))

if ( skip_points == 0 ) {
	boot_line_plot = boot_line_plot + geom_point( data=data, aes(count, boot_time, colour=testname, group=dataset), alpha=0.3)
}

	# And get a zero Y index plot.
	boot_line_plot_zero = boot_line_plot + ylim(0, NA) +
		ggtitle("Pod boot time (0 index)")

# Show how boot time changed
delete_line_plot <- ggplot() +
	geom_line( data=data, aes(count, delete_time, colour=testname, group=dataset), alpha=0.2) +
	geom_smooth( data=data, aes(count, delete_time, colour=testname, group=dataset), se=FALSE, method="loess", size=0.3) +
	xlab("parallel pods") +
	ylab("Delete time (s)") +
	ggtitle("Pod deletion time (detail)") +
	#ylim(0, NA) + # For big machines, better to not 0-index
	theme(axis.text.x=element_text(angle=90))

if ( skip_points == 0 ) {
	delete_line_plot = delete_line_plot + geom_point( data=data, aes(count, delete_time, colour=testname, group=dataset), alpha=0.3)
}

	# And get a 0 indexed Y axis plot
	delete_line_plot_zero = delete_line_plot + ylim(0, NA) +
		ggtitle("Pod deletion time (0 index)")

# See https://www.r-bloggers.com/ggplot2-easy-way-to-mix-multiple-graphs-on-the-same-page/ for
# excellent examples
master_plot = grid.arrange(
	boot_line_plot_zero,
	delete_line_plot_zero,
	boot_line_plot,
	delete_line_plot,
	nrow=2,
	ncol=2 )

