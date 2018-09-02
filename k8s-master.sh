#!/usr/bin/env bash

. ./config.properties
. ./k8s-common.sh

cert_etcd(){
    sudo mkdir -p /etc/kubernetes/ca/etcd

    cp ./target/ca/etcd/etcd-csr.json /etc/kubernetes/ca/etcd/
    cd /etc/kubernetes/ca/etcd/

    sudo cfssl gencert \
        -ca=/etc/kubernetes/ca/ca.pem \
        -ca-key=/etc/kubernetes/ca/ca-key.pem \
        -config=/etc/kubernetes/ca/ca-config.json \
        -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
}

cert_apiserver(){
    sudo mkdir -p /etc/kubernetes/ca/kubernetes

    sudo cp ./target/ca/kubernetes/kubernetes-csr.json /etc/kubernetes/ca/kubernetes/
    cd /etc/kubernetes/ca/kubernetes/

    sudo cfssl gencert \
        -ca=/etc/kubernetes/ca/ca.pem \
        -ca-key=/etc/kubernetes/ca/ca-key.pem \
        -config=/etc/kubernetes/ca/ca-config.json \
        -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes

    local random_tmp=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
    echo ""
    echo "######## kube-apiserver token: ${random_tmp},kubelet-bootstrap,10001,\"system:kubelet-bootstrap\""
    echo "${random_tmp},kubelet-bootstrap,10001,\"system:kubelet-bootstrap\"" > \
            /etc/kubernetes/ca/kubernetes/token.csv
}

cert_kubectl(){
    sudo mkdir -p /etc/kubernetes/ca/admin

    sudo cp ./target/ca/admin/admin-csr.json /etc/kubernetes/ca/admin/

    cd /etc/kubernetes/ca/admin/

    sudo cfssl gencert \
        -ca=/etc/kubernetes/ca/ca.pem \
        -ca-key=/etc/kubernetes/ca/ca-key.pem \
        -config=/etc/kubernetes/ca/ca-config.json \
        -profile=kubernetes admin-csr.json | cfssljson -bare admin
}

bind_kubelet_bootstrap(){
    sudo kubectl -n kube-system get clusterrole

    sudo kubectl create clusterrolebinding kubelet-bootstrap \
         --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap

}

start_etcd(){
    if [ "${CERT_MODE}" != "simple" ]; then
        cert_etcd
        cd ${base_dir}
    fi
    sudo cp ./target/master-node/etcd.service /lib/systemd/system/
    sudo systemctl enable etcd.service
    sudo mkdir -p /var/lib/etcd
    sudo rm -rf /var/lib/etcd/*
    echo ""
    echo "######## start etcd service #########"
    sleep 2s
    cat /lib/systemd/system/etcd.service
    echo ""
    echo ""
    sudo service etcd restart
    echo "start etcd completed"
}

start_apiserver(){
    if [ "${CERT_MODE}" != "simple" ]; then
        cert_apiserver
        cd ${base_dir}
    fi
    sudo cp ./target/master-node/kube-apiserver.service /lib/systemd/system/
    echo ""
    echo "######## start kube-apiserver service #########"
    sleep 2s
    cat /lib/systemd/system/kube-apiserver.service
    echo ""
    echo ""
    sudo systemctl enable kube-apiserver.service
    echo "######## stop old kube-apiserver service #########"
    sudo service kube-apiserver stop
    sudo service kube-apiserver start
    echo "start kube-apiserver completed"
}

start_controlmanager(){
    sudo cp ./target/master-node/kube-controller-manager.service /lib/systemd/system/
    sudo systemctl enable kube-controller-manager.service
    echo ""
    echo "######## start kube-controller-manager service #########"
    sleep 2s
    cat /lib/systemd/system/kube-controller-manager.service
    echo ""
    echo ""
    sudo service kube-controller-manager restart
    echo "start kube-controller-manager completed"
}

start_scheduler(){
    sudo cp ./target/master-node/kube-scheduler.service /lib/systemd/system/
    sudo systemctl enable kube-scheduler.service
    echo ""
    echo "######## start kube-scheduler service #########"
    sleep 2s
    cat /lib/systemd/system/kube-scheduler.service
    echo ""
    echo ""
    sudo service kube-scheduler restart
    echo "start kube-scheduler completed"
}

start_kubectl(){
    if [ "${CERT_MODE}" == "simple" ]; then
        sudo kubectl config set-cluster kubernetes  --server=http://${MASTER_IP}:8080
        sudo kubectl config set-context kubernetes --cluster=kubernetes
        sudo kubectl config use-context kubernetes
    else
        cert_kubectl
        cd ${base_dir}
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

start_kubedns(){
    sudo kubectl create -f ./target/services/kube-dns.yaml
}

copy_worknode(){
    local i=0
    local host=""
    local extIP=""
    local internalIP=""
    local username=""
    local passwd=""
    for key in ${DOMAIN[@]}
    do
         b=$((i%5))
        if [ $b -eq 0 ]; then
            host=${key}
        elif [ $b -eq 1 ]; then
            extIP=${key}
        elif [ $b -eq 2 ]; then
            internalIP=${key}
        elif [ $b -eq 3 ]; then
            username=${key}
        else
            passwd=${key}

            if [ $i -gt 5 ];then
                echo ""
                echo "######## sync kubernetes file to worknode #########"
                sleep 3s

                echo "######## shutdown worknode service now ##########"
                ssh ${username}@${internalIP} "service kube-calico stop;service kubelet stop && rm -fr /var/lib/kubelet/* ; rm -rf ${base_dir};rm -rf /etc/kubernetes"

                scp -r ${base_dir} ${username}@${internalIP}:${base_dir}
                scp -r /etc/kubernetes ${username}@${internalIP}:/etc/kubernetes
            fi
        fi

        ((i++))
    done


  #  for servernode in ${DOMAIN[@]}
  #  do

  #      [ i ne 0 ] && rsync -avu --progress --delete ${base_dir} ${servernode[3]}@${servernode[2]}:${base_dir}
  #      ((i++))
  #  done
}

start_worknode_scenario(){

    local i=0
    local host=""
    local extIP=""
    local internalIP=""
    local username=""
    local passwd=""
    for key in ${DOMAIN[@]}
    do
         b=$((i%5))
        if [ $b -eq 0 ]; then
            host=${key}
        elif [ $b -eq 1 ]; then
            extIP=${key}
        elif [ $b -eq 2 ]; then
            internalIP=${key}
        elif [ $b -eq 3 ]; then
            username=${key}
        else
            passwd=${key}

            if [ $i -gt 5 ];then
                echo ""
                echo "######## start deploy worknode ,username:${username}, IP: ${internalIP} #########"
                sleep 3s

                    ssh -t  ${username}@${internalIP} \
                        "cd ${base_dir};chmod +x ${base_dir}/k8s.sh;sudo /bin/bash ${base_dir}/k8s.sh worknode"

            fi
        fi

        ((i++))
    done

 #   for servernode in ${DOMAIN[@]}
 #   do
 #       if [ i ne 0 ];then
 #           ssh -T  $servernode[3]@$servernode[2] << EOF1
 #               chmod +x ${base_dir}/k8s.sh
 #               sudo /bin/bash ${base_dir}/k8s.sh worknode
#EOF1
  #      fi
  #      ((i++))
  #  done
}


setup_master_kubernetes_env(){
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

start_masternode_scenario(){

    setup_master_kubernetes_env

    if [ "${CERT_MODE}" != "simple" ]; then
        install_cfssl
        gen_rootCert
        cd ${base_dir}
    fi

    echo ""
    local p=$(pwd)
    local q=`pwd`
    echo "####### start service: $p,$q#######"

    start_etcd
    start_apiserver
    start_controlmanager
    start_scheduler

    echo ""
    echo "################ prepare start calico ############"
    sleep 10s
    start_calico
    echo "################start calico completed###########"
    sleep 1s

    start_kubectl

    if [ "${CERT_MODE}" != "simple" ]; then
        bind_kubelet_bootstrap
    fi

    cd ${base_dir}

    start_kubedns

    copy_worknode

    start_worknode_scenario
    echo ""
    echo "############ start worknode completed ########"

    sudo kubectl get csr|grep 'Pending' | awk '{print $1}'| xargs kubectl certificate approve
    echo "############ Accepted worknode request ########"

}



start_masternode_scenario

