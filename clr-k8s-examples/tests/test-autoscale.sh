kubectl run php-apache-test --image=k8s.gcr.io/hpa-example --requests=cpu=200m --expose --port=80
kubectl autoscale deployment php-apache-test --cpu-percent=50 --min=1 --max=10
kubectl get hpa

#kubectl run -i --tty load-generator --image=busybox /bin/sh
# while true; do wget -q -O- http://php-apache-test.default.svc.cluster.local; done
