pipeline {
	agent {
		label 'clearlinux'
	}
	options {
		timeout(time: 1, unit: "HOURS")
	}
	triggers {
		cron('H */12 * * *')
	}
	environment {
		CLR_K8S_PATH="${env.WORKSPACE}/clr-k8s-examples"
	}
	stages {
		stage('Setup system') {
			steps {
				dir(path: "$CLR_K8S_PATH") {
					sh './setup_system.sh'
				}
			}
		}
		stage('Init') {
			steps {
				dir(path: "$CLR_K8S_PATH") {
					sh './create_stack.sh init'
					sh 'mkdir -p $HOME/.kube'
					sh 'sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config'
					sh 'sudo chown $(id -u):$(id -g) $HOME/.kube/config'
					sh 'kubectl version'
				}
			}
		}
		stage('CNI') {
			steps {
				dir(path: "$CLR_K8S_PATH") {
					sh './create_stack.sh cni'
					sh 'kubectl rollout status deployment/coredns -n kube-system --timeout=5m'
					sh 'kubectl get pods -n kube-system'
				}
			}
		}
		stage('Reset Stack') {
			steps {
				dir(path: "$CLR_K8S_PATH") {
					sh './reset_stack.sh'
				}
			}
		}
	}
	post {
		always {
			sh 'uname -a'
			sh 'swupd info'
		}
	}
}
