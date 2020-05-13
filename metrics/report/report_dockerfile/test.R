
suppressMessages(library(jsonlite))			# to load the data.

options(digits=22)

x=fromJSON('{"ns": 1567002188374607769}')

print(x)
print(fromJSON('{"ns": 1567002188374607769}'), digits=22)
