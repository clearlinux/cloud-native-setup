#!/usr/bin/env Rscript
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Show pod communication latency

suppressMessages(suppressWarnings(library(ggplot2)))	# ability to plot nicely.
suppressWarnings(suppressWarnings(library(ggpubr)))	# ggtexttable
suppressMessages(library(jsonlite))			# to load the data.
suppressMessages(library(scales))			# For de-science notation of axis
library(tibble)						# tibbles for tidy data

testnames=c(
	"k8s-rapid-nc"
)

### For developers: uncomment following variables to run this as is in R
# resultdirs=c("PATH/TO/RES1/", ...) # keep the ending slash on result paths
# inputdir=""

latencydata=c()

# iterate over every set of results (test run)
for (currentdir in resultdirs) {
	# For every results file we are interested in evaluating
	for (testname in testnames) {
		matchdir=paste(inputdir, currentdir, sep="")
		matchfile=paste(testname, '\\.json', sep="")
		files=list.files(matchdir, pattern=matchfile)

		# For every matching results file
		for (ffound in files) {
			fname=paste(inputdir, currentdir, ffound, sep="")
			if (!file.exists(fname)) {
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

			# All the data we are looking for comes in BootResults,
			# so pick it out to make referencing easier
			br=fdata$BootResults

			########################################################
			#### Now extract latency time percentiles (ltp) ########
			########################################################
			ltp=br$latency_time$Percentiles
			# Percentile thresholds, for example [5, 25, 50, 75, 95]
			ltp_perc=fdata$Config$nc_percentiles[[1]]
			perc_count = length(ltp_perc)
			# Measured times
			ltp_meas=matrix(unlist(ltp), nrow=perc_count)
			# Build latency percentiles tibble with nice headings
			ltpt=tibble(n_pods=br$n_pods$Result)
			for (n in seq(perc_count)) {
				p_title = paste0("p", ltp_perc[n])
				ltpt[p_title] = ltp_meas[n,]
			}
			# ltpt example: with percentiles [5, 50, 95]:
			# n_pods  p5  p50  p95
			#    100   4	8   10
			#    200   5   11   15
			#    300   6   14   19
			ltpt$testname=testname
			latencydata=rbind(latencydata, ltpt)
		}
	}
}

# Visualize data.
if (length(latencydata[[1]]) <= 5 || length(unique(latencydata$testname)) > 1) {
	# If there are many tests to compare or only few data points, use boxplot with extra percentile points.
	latp = ggplot(data=latencydata, aes(x=n_pods)) + ylab("Latency (us)") + xlab("pods") + scale_y_continuous(labels=comma)
	perc_mid = floor((perc_count)/2)
	# Create boxplot around the middle percentile
	if (perc_count >= 3) {
		box_bottom=names(ltpt)[perc_mid+1]
		box_mid=names(ltpt)[perc_mid+2]
		box_top=names(ltpt)[perc_mid+3]
		if (perc_count >= 5) {
			whis_low=names(ltpt)[perc_mid]
			whis_high=names(ltpt)[perc_mid+4]
			latp = latp + geom_boxplot(aes_string(group="interaction(testname,n_pods)",ymin=whis_low,lower=box_bottom,middle=box_mid,upper=box_top,ymax=whis_high,fill="testname"),stat="identity")
		} else {
			latp = latp + geom_boxplot(aes_string(group="interaction(testname,n_pods)",lower=box_bottom,middle=box_mid,upper=box_top,fill="testname"),stat="identity")
		}
	}
	# Boxplot (above) covers at most 5 percentiles around the center (median).
	# Visualize the rest using a point for each percentile.
	if (perc_count > 5) {
		for (n in seq(1, (perc_count-5)/2)) {
			lower_name=names(ltpt)[n+1]
			upper_name=names(ltpt)[perc_count-n+2]
			latp = latp + geom_point(aes_string(group="interaction(testname,n_pods)",y=lower_name, color="testname"))
			latp = latp + geom_point(aes_string(group="interaction(testname,n_pods)",y=upper_name, color="testname"))
		}
	}
} else {
	# Use colored areas and median lines when there are many ticks on X axis
	latp = ggplot(data=latencydata, aes(x=n_pods)) + ylab("Latency (us)") + xlab("pods") + scale_y_continuous(labels=comma)
	perc_mid = floor((perc_count)/2)
	perc_maxdist = perc_mid
	plot_number = 0
	for (plot_test in unique(latencydata$testname)) {
		plot_number = plot_number + 1
		for (n in seq(perc_mid)) {
			# First fill outmost areas, like p5..p25 and p75..p95,
			# then areas closer to the middle, like p25..p50 and p50..p75
			lower_name = names(ltpt)[n+1]
			lower_next_name = names(ltpt)[n+2]
			upper_name = names(ltpt)[perc_count-n+2]
			upper_prev_name = names(ltpt)[perc_count-n+1]
			alpha = 0.7 * ((n+1) / (perc_mid+1))**2
			latp = latp + geom_ribbon(data=latencydata[latencydata$testname==plot_test,],aes_string(x="n_pods",ymin=lower_name,ymax=lower_next_name,fill="testname"),alpha=alpha)
			latp = latp + geom_ribbon(data=latencydata[latencydata$testname==plot_test,],aes_string(x="n_pods",ymin=upper_prev_name,ymax=upper_name,fill="testname"),alpha=alpha)
		}
		median_index = match("p50", names(ltpt))
		if (!is.na(median_index)) {
			# Draw median line
			latp = latp + geom_line(data=latencydata[latencydata$testname==plot_test,],aes_string(x="n_pods",y=names(ltpt)[median_index],color="testname"))
		}
	}
}

# Table presentation.
lat_table=c()
for (testname in unique(latencydata$testname)) {
	testlines=latencydata[latencydata$testname==testname,]
	lat_table=rbind(lat_table,testlines[1,])
	if (length(testlines) > 3) {
		# middle pod count
		lat_table=rbind(lat_table,testlines[(length(testlines)-1)/2,])
	}
	if (length(testlines) > 2) {
		# max pod count
		lat_table=rbind(lat_table,testlines[length(testlines)-1,])
	}
}
latt=ggtexttable(lat_table,rows=NULL)

cat("\n\nLatency percentiles illustrated in the Figure below: ", paste0(ltp_perc, "\\%"), "\n\n")

page1 = grid.arrange(latp, latt, ncol=1)

# pagebreak, as the graphs overflow the page otherwise
cat("\n\n\\pagebreak\n")
