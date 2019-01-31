#!/bin/bash

input="test-cpumanager.yaml.tmpl"

filename() {
	echo "test-cpumanager-$1.yaml"
}

for runtimeclass in runc kata-qemu kata-fc; do
	output=$(filename $runtimeclass)
	cp $input $output
	sed -i "s/__runtimeclass__/$runtimeclass/g" $output
	if [ $runtimeclass == "runc" ]; then continue; fi

	insertline="\ \ runtimeClassName: $runtimeclass"
	sed -i "/spec:/a $insertline" $output
done
kubectl apply -f .
