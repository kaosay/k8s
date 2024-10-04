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


## 安装必要的工具
#function install_tools() {
#    echo "安装必要的工具..."
#    sudo apt-get update
#    sudo apt-get install -y apt-transport-https ca-certificates curl
#    sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
#    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
#    sudo apt-get update
#    sudo apt-get install -y kubelet kubeadm kubectl
#    sudo apt-mark hold kubelet kubeadm kubectl
#    echo "工具安装完成."
#}

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
    echo "安装网络插件 Calico..."
    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    echo "网络插件安装完成."
}

# 安装 Ingress-Nginx
function install_ingress_nginx() {
    echo "安装 Ingress-Nginx..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
    echo "Ingress-Nginx 安装完成."
}

# 配置 Ingress-Nginx 为 DaemonSet
function configure_ingress_nginx_daemonset() {
    echo "配置 Ingress-Nginx 为 DaemonSet..."
    # 删除默认的 Ingress-Nginx 控制器
    kubectl delete deployment ingress-nginx-controller -n ingress-nginx

    # 创建 DaemonSet 配置
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  selector:
    matchLabels:
      app: ingress-nginx
  template:
    metadata:
      labels:
        app: ingress-nginx
    spec:
      containers:
        - name: controller
          image: quay.io/kubernetes-ingress-controller/nginx-ingress-controller:latest
          args:
            - /nginx-ingress-controller
            - --configmap=\$(POD_NAMESPACE)/ingress-nginx-controller
            - --tcp-services-configmap=\$(POD_NAMESPACE)/ingress-nginx-tcp
            - --udp-services-configmap=\$(POD_NAMESPACE)/ingress-nginx-udp
            - --default-backend-service=\$(POD_NAMESPACE)/ingress-nginx-default-backend
          ports:
            - name: http
              containerPort: 80
            - name: https
              containerPort: 443
      serviceAccountName: ingress-nginx
EOF
    echo "Ingress-Nginx DaemonSet 配置完成."
}

# 主函数
function main() {
	
	set_ubuntu
	install_containerd
	install_k8s

   #install_tools
    init_kubernetes
    #install_network_plugin
    #install_ingress_nginx
    #configure_ingress_nginx_daemonset
    echo "Kubernetes 和 Ingress-Nginx 安装完成."
}

# 执行主函数
main

