#!/usr/bin/env bash

. ./config.properties


get_base_dir(){
    base_dir=$(cd "$(dirname "$0")";pwd)
    echo "########current directory: ${base_dir}####"
}


do_install_module(){
    sudo apt-get update

    sudo apt-get install curl

    sudo apt-get install wget

    apt-get install scp
}

do_install_docker(){
    read -p "Please check whether need to install(re-install) docker? Y/N (Default N):" selected
    [ -z "${selected}" ] && selected="N"
    if [ "${selected}" == "y" ] || [ "${selected}" == "Y" ]; then
        echo ""
        echo ""
        echo "##############install docker engine ##############"

        sudo apt-get remove docker docker-engine docker.io

        curl -fsSL get.docker.com -o get-docker.sh

        sudo sh get-docker.sh
     fi
}


update_host(){
    echo ""
    echo ""
    echo "###############Prepare setup cluster hostname#######"

    sudo sed -i "/ k8s_/d" /etc/hosts

  #  i=0
  #  for key in ${CLUSTER_IP_LIST[@]}
  #  do
  #      sudo echo "Register IP: ${key},hostname: k8s_${HOSTNAME_LIST[i]} in hosts"
  #      sudo echo "$key k8s_${HOSTNAME_LIST[i]}" >> /etc/hosts

  #      if [ "${NODE_IP}" == "$key" ];then
  #          sudo sysctl kernel.hostname=k8s_${HOSTNAME_LIST[i]}
  #          sudo echo "$k8s_{HOSTNAME_LIST[i]}" > /etc/hostname
  #      fi
  #     # i=$i+1
  #      ((i++))
  #  done

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

            sudo echo "Register IP: ${internalIP},hostname: k8s_${host},index: $i in hosts"
            sudo echo "${internalIP} k8s_${host}" >> /etc/hosts

            if [ $i -lt 5 ]; then
                MASTER_IP=${internalIP}

                if [ "${CERT_MODE}" == "simple" ]; then
                    ETCD_ENDPOINTS=http://${MASTER_IP}:2379
                else
                    ETCD_ENDPOINTS=https://${MASTER_IP}:2379
                fi

                sudo echo "####### Master IP: ${internalIP},Node IP: ${internalIP} , etcd Endpoint:${ETCD_ENDPOINTS} ####"
            fi

            local inets=`sudo ifconfig -a|grep 'inet '| awk '{print $2}' | grep -v '127.0.0.1'`
            for key in ${inets[@]}
            do
                if [ "${internalIP}" == "$key" ];then
                    NODE_IP=${internalIP}
                    echo "########## verify current node ip success: ${NODE_IP}"
                fi
            done
        fi

       # i=$i+1
        ((i++))
    done

}

enable_datapackage_forward(){
    echo ""
    echo ""
    echo "############enable datapackage forward#####"

    if ! grep "^ExecStartPost=" /lib/systemd/system/docker.service;then

        sudo sed -i "/^ExecStart=/ i\ExecStartPost=\/sbin\/iptables -I FORWARD -s 0.0.0.0/0 -j ACCEPT " \
            /lib/systemd/system/docker.service
    fi

    sudo systemctl daemon-reload
    sudo service docker start

    #${K8S_CONF}: /etc/sysctl.d/k8s.conf
    sudo cat << EOF > /etc/sysctl.d/k8s.conf
       net.ipv4.ip_forward = 1
       net.bridge.bridge-nf-call-ip6tables = 1
       net.bridge.bridge-nf-call-iptables = 1
EOF
    sudo sysctl -p /etc/sysctl.d/k8s.conf
    echo ""
    echo "####### enable iptable forwarod completed#######"
    return 0
}



cert_calico(){
    sudo mkdir -p /etc/kubernetes/ca/calico

    sudo cp ./target/ca/calico/calico-csr.json /etc/kubernetes/ca/calico/
    cd /etc/kubernetes/ca/calico/

    sudo cfssl gencert \
        -ca=/etc/kubernetes/ca/ca.pem \
        -ca-key=/etc/kubernetes/ca/ca-key.pem \
        -config=/etc/kubernetes/ca/ca-config.json \
        -profile=kubernetes calico-csr.json | cfssljson -bare calico

}

start_calico(){
    if [ "${CERT_MODE}" != "simple" ]; then
        cert_calico
        cd ${base_dir}
    fi
    sudo cp ./target/all-node/kube-calico.service /lib/systemd/system/
    sudo systemctl enable kube-calico.service
    sudo service kube-calico restart

    echo ""
    echo "start kube-calico completed"
}

verify_inet(){
    local inets=`sudo ifconfig -a|grep 'inet '| awk '{print $2}' | grep -v '127.0.0.1'`

    for key in ${inets[@]}
    do
        if [ "${MASTER_IP}" == "$key" ];then
            echo "########## verify master node ip success: ${MASTER_IP}"
            return 0
        fi
    done

    #for key in ${inets[@]}
    #do
    #    for nodeip in ${WORKNODE_LIST[@]}
    #    do
    #        if [ "${nodeip}" == "$key" ];then
    #            NODE_IP = ${nodeip}
    #            return 0
    #        fi
    #    done
    #done

    for key in ${inets[@]}
    do
        if [ "${NODE_IP}" == "$key" ];then
            echo "########## verify work node ip success: ${NODE_IP}"
            return 1
        fi
    done

    echo "########## verify node ip failed "
    return 2
}

install_kubernete_bin(){
    echo ""
    echo ""

    echo "###################unzip kubernete file.....######"
    #sudo tar zxvf ./kubernetes-bins.tar.gz

    sudo mkdir -p ./kubernetes-bins
    cd ./kubernetes-tarbins
    for tar in *.tar.gz;  do tar xvf $tar -C ../kubernetes-bins; done
    cd ..
    sudo mkdir -p ${BIN_PATH}
    echo ""
    echo "###################install kubernete file.....######"
    sudo cp -rf ./kubernetes-bins/* ${BIN_PATH}/
    sudo rm -rf ./kubernetes-bins

    echo "install kubernete file completed"
}

install_cfssl(){
    sudo wget -q --show-progress --https-only --timestamping \
            https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 \
            https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64

    chmod +x ./cfssl_linux-amd64 ./cfssljson_linux-amd64

    mv ./cfssl_linux-amd64 /usr/local/bin/cfssl

    mv ./cfssljson_linux-amd64 /usr/local/bin/cfssljson
}

gen_rootCert(){
    sudo mkdir -p /etc/kubernetes/ca

    sudo cp ./target/ca/ca-config.json /etc/kubernetes/ca
    sudo cp ./target/ca/ca-csr.json /etc/kubernetes/ca

    cd /etc/kubernetes/ca
    sudo cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}

