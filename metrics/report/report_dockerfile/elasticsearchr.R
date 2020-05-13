
library('elasticsearchr')

for_scaling <- query('{
"bool": {
	"must": [
	{ "match":
		{
			"test.testname": "k8s scaling"
		}
	}
	]
}
}')

these_fields <- select_fields('{
	"includes": [
		"date.Date",
		"k8s-scaling.BootResults.launch_time.Result",
		"k8s-scaling.BootResults.n_pods.Result"
	]
}')

sort_by_date <- sort_on('[{"date.Date": {"order": "asc"}}]')

x=elastic("http://192.168.0.111:9200", "logtest") %search% (for_scaling + sort_by_date + these_fields)
