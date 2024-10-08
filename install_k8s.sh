#!/bin/bash

# close swap,set network and so on.
set_ubuntu(){
	echo -e "\n ==> ----close swap..."
	swapoff -a
	sed -i '/swap/ s/^/#/' /etc/fstab

	echo "----Setting net.bridge.bridge-nf-call-iptables = 1----"

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

	sysctl --system
}

# install cri-containerd-cni-1.7.22-linux-amd64.tar.gz
install_containerd(){
	echo -e "\n ==> ----Installing cri-containerd-cni-1.7.22-linux-amd64.tar.gz----"
	tar xvf ./cri-containerd-cni-1.7.22-linux-amd64.tar.gz -C /
	
	test -d /etc/containerd || mkdir /etc/containerd
	cp ./config.toml /etc/containerd

# load containerd core module
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

	modprobe overlay
	modprobe br_netfilter
	
	systemctl enable containerd --now
	systemctl status containerd| head

	containerd --version	
}

# install k8s
install_k8s(){
	echo -e "\n ==> ----Installing k8s----"
	apt-get update && apt-get install -y apt-transport-https

	test -d /etc/apt/keyrings || mkdir /etc/apt/keyrings

	curl -fsSL https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.30/deb/Release.key |
	gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

	echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.30/deb/ /" | 
	tee /etc/apt/sources.list.d/kubernetes.list
	apt-get update
	apt-get install -y kubelet kubeadm kubectl

	echo "--------Setting kubelet--------"
cat <<EOF | tee /usr/lib/systemd/system/kubelet.service.d/10-proxy-ipvs.conf
# 启用 ipvs 相关内核模块
[Service]
ExecStartPre=-/sbin/modprobe ip_vs
ExecStartPre=-/sbin/modprobe ip_vs_rr
ExecStartPre=-/sbin/modprobe ip_vs_wrr
ExecStartPre=-/sbin/modprobe ip_vs_sh
EOF
	systemctl daemon-reload
	systemctl enable kubelet --now
	
	systemctl status kubelet| head

	kubelet --version
	kubeadm version
	kubectl version
	echo "----sleep 10"
	sleep 10
}


# 初始化 Kubernetes
function init_kubernetes() {
    echo -e "\n ==> ....初始化 Kubernetes...."
    #sudo kubeadm init --pod-network-cidr=192.168.0.0/16

	kubeadm init \
        --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers \
        --pod-network-cidr 192.168.0.0/16 \
        --cri-socket /run/containerd/containerd.sock \
        --v 5 \
       
        echo "Kubernetes 初始化完成."

    # 配置 kubectl
    echo "配置 kubectl..."
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    echo "kubectl 配置完成."
}

# 安装网络插件 (Calico)
function install_network_plugin() {
    echo -e "\n  ==>  安装网络插件 Calico..."
    #kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

	wget https://docs.projectcalico.org/manifests/calico.yaml
	sed -i 's/docker.io/docker.linkos.org/g' ./calico.yaml
	kubectl apply -f ./calico.yaml
	
    echo "网络插件安装完成."
}

# 安装 Ingress-Nginx
function install_ingress_nginx() {
    echo -e "\n ==> 安装 Ingress-Nginx..."
    #kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

	#wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/cloud/deploy.yaml
	#sed -i 's/@sha.*//g' ./deploy.yaml
	#sed -i 's/registry.k8s.io\/ingress-nginx/registry.cn-hangzhou.aliyuncs.com\/google_containers/g' ./deploy.yaml
	
	# remove taint of master node
	kubectl taint node `hostname` node-role.kubernetes.io/control-plane:NoSchedule-
	kubectl apply -f ./ingress-nginx.yaml

	echo -e "\n  ==>  sleep 5 for Ingress nginx-----------------------"
	sleep 5
	kubectl get pod -A

    echo "Ingress-Nginx 安装完成."
}

# 主函数
function main() {
	
	set_ubuntu
	install_containerd
	install_k8s

    init_kubernetes
    install_network_plugin
    install_ingress_nginx

    echo "Kubernetes 和 Ingress-Nginx 安装完成."
}

# 执行主函数
main

