#!/usr/bin/en

. ./config.properties
. ./k8s-common.sh

create_bootstrap_kubeconfig(){
    local token=`cat /etc/kubernetes/ca/kubernetes/token.csv | awk -F "," {'print $1'}`

    sudo kubectl config set-cluster kubernetes \
        --certificate-authority=/etc/kubernetes/ca/ca.pem \
        --embed-certs=true \
        --server=https://${MASTER_IP}:6443 \
        --kubeconfig=bootstrap.kubeconfig
    sudo kubectl config set-credentials kubelet-bootstrap \
        --token=${token}\
        --kubeconfig=bootstrap.kubeconfig

    sudo kubectl config set-context default \
        --cluster=kubernetes \
        --user=kubelet-bootstrap \
        --kubeconfig=bootstrap.kubeconfig

    sudo kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

    sudo mv bootstrap.kubeconfig /etc/kubernetes/

    cp ./target/worker-node/10-calico.conf /etc/cni/net.d/
}

start_kubectl(){
    if [ "${CERT_MODE}" == "simple" ]; then
        sudo kubectl config set-cluster kubernetes  --server=http://${MASTER_IP}:8080
        sudo kubectl config set-context kubernetes --cluster=kubernetes
        sudo kubectl config use-context kubernetes
    else
        sudo kubectl config set-cluster kubernetes \
            --certificate-authority=/etc/kubernetes/ca/ca.pem \
            --embed-certs=true \
            --server=https://${MASTER_IP}:6443

        sudo  kubectl config set-credentials admin \
            --client-certificate=/etc/kubernetes/ca/admin/admin.pem \
            --embed-certs=true \
            --client-key=/etc/kubernetes/ca/admin/admin-key.pem

        sudo kubectl config set-context kubernetes \
            --cluster=kubernetes --user=admin

        sudo kubectl config use-context kubernetes

        cp ./target/worker-node/10-calico.conf /etc/cni/net.d/

    fi
}

cert_kube_proxy(){

    sudo mkdir -p /etc/kubernetes/ca/kube-proxy
    sudo cp ./target/ca/kube-proxy/kube-proxy-csr.json /etc/kubernetes/ca/kube-proxy/
    cd /etc/kubernetes/ca/kube-proxy/

    sudo cfssl gencert \
        -ca=/etc/kubernetes/ca/ca.pem \
        -ca-key=/etc/kubernetes/ca/ca-key.pem \
        -config=/etc/kubernetes/ca/ca-config.json \
        -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
}

start_kubelet(){
    sudo mkdir -p /var/lib/kubelet
    sudo rm -rf /var/lib/kubelet/*
    sudo mkdir -p /etc/kubernetes
    sudo mkdir -p /etc/cni/net.d

    echo ""
    echo "######## start kubelet service #########"

    if [ "${CERT_MODE}" != "simple" ]; then
        create_bootstrap_kubeconfig
    else
        sudo cp ./target/worker-node/kubelet.kubeconfig /etc/kubernetes/
    fi

    cd ${base_dir}

    sudo cp ./target/worker-node/kubelet.service /lib/systemd/system/
    sudo cp ./target/worker-node/10-calico.conf /etc/cni/net.d/

    sleep 2s
    cat /lib/systemd/system/kubelet.service
    echo ""
    echo ""

    sudo systemctl enable kubelet.service
    sudo systemctl daemon-reload
    sudo service kubelet stop
    sudo service kubelet start

    echo ""
    echo "start kubelet completed"
}

gen_kubeproxy_config(){

    sudo kubectl config set-cluster kubernetes \
        --certificate-authority=/etc/kubernetes/ca/ca.pem \
        --embed-certs=true \
        --server=https://${MASTER_IP}:6443 \
        --kubeconfig=kube-proxy.kubeconfig

    sudo kubectl config set-credentials kube-proxy \
        --client-certificate=/etc/kubernetes/ca/kube-proxy/kube-proxy.pem \
        --client-key=/etc/kubernetes/ca/kube-proxy/kube-proxy-key.pem \
        --embed-certs=true \
        --kubeconfig=kube-proxy.kubeconfig

    sudo kubectl config set-context default \
        --cluster=kubernetes \
        --user=kube-proxy \
        --kubeconfig=kube-proxy.kubeconfig

    sudo kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

    sudo mv kube-proxy.kubeconfig /etc/kubernetes/kube-proxy.kubeconfig
}

start_kubeproxy(){
    sudo mkdir -p /var/lib/kube-proxy
    sudo rm -rf /var/lib/kube-proxy/*
    sudo cp ./target/worker-node/kube-proxy.service /lib/systemd/system/

    if [ "${CERT_MODE}" != "simple" ]; then
        cert_kube_proxy
        gen_kubeproxy_config
        sudo apt install conntrack
    else
        sudo cp target/worker-node/kube-proxy.kubeconfig /etc/kubernetes/
    fi

    sudo systemctl enable kube-proxy.service

    sudo service kube-proxy restart

    echo ""
    echo "start kube-proxy completed"
}

setup_worknode_kubernetes_env(){
    get_base_dir

    do_install_module

    do_install_docker

    enable_datapackage_forward

    update_host

    echo ""
    echo ""
    echo "####################generate kubernetes config file#####"
    if [ "${CERT_MODE}" == "simple" ]; then
        . ./gen-config.sh simple
    else
        . ./gen-config.sh with-ca
    fi
    cd ${base_dir}
    install_kubernete_bin
}

start_worknode_scenario(){
    setup_worknode_kubernetes_env

    if [ "${CERT_MODE}" != "simple" ]; then
        install_cfssl
        cd ${base_dir}
    fi

    echo ""
    echo "################ prepare start calico ############"
    sleep 10s
    start_calico
    echo "################start calico completed###########"
    sleep 1s

    #start_kubectl

    start_kubelet
    start_kubeproxy
}

start_worknode_scenario