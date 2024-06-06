
#!/bin/bash
export docker_net_interface="br-$(docker network ls -f name=minikube -q)"
export localip=`ip route get $(ip route show 0.0.0.0/0 | grep -oP 'via \K\S+') | grep -oP 'src \K\S+'`
export minikubeip=`minikube ip`

if ! sudo iptables -L DOCKER -v -n | grep $minikubeip | egrep ':443' &>/dev/null; then 
    sudo iptables -A DOCKER -p tcp --dport 443 -j ACCEPT
    sudo iptables -A DOCKER -d ${minikubeip}/32 ! -i $docker_net_interface -o $docker_net_interface -p tcp -m tcp --dport 80 -j ACCEPT
    sudo iptables -A DOCKER -d ${minikubeip}/32 ! -i $docker_net_interface -o $docker_net_interface -p tcp -m tcp --dport 443 -j ACCEPT
    sudo iptables -t nat -A POSTROUTING -s ${minikubeip}/32 -d ${minikubeip}/32 -p tcp -m tcp --dport 80 -j MASQUERADE
    sudo iptables -t nat -A POSTROUTING -s ${minikubeip}/32 -d ${minikubeip}/32 -p tcp -m tcp --dport 443 -j MASQUERADE
    sudo iptables -t nat -A DOCKER -d ${localip}/32 ! -i $docker_net_interface -p tcp -m tcp --dport 80 -j DNAT --to-destination ${minikubeip}:80
    sudo iptables -t nat -A DOCKER -d ${localip}/32 ! -i $docker_net_interface -p tcp -m tcp --dport 443 -j DNAT --to-destination ${minikubeip}:443
fi
