  #!/usr/bin/bash
  #########################################################################
  # ICP4D 3.0.1 auto-provisioning script on Fyre for CPD, WD and EMA only #  
  #########################################################################

  echo
  echo "START Installing"
  echo
  
  # Setup basic environment variables
  source provision.env

  MASTER_HOST=${FYRE_CLUSTER_PREFIX}-${FYRE_MASTER}	
  for (( i=1 ; i<=${N_WORKER} ; i++ )); do
    HOSTS="${HOSTS} ${FYRE_CLUSTER_PREFIX}-${FYRE_WORKER}-${i}"
  done
  
  function kernelSetting {
    ssh ${MASTER_HOST} "cat << EOF >> /etc/sysctl.d/42-cp4d.conf
    kernel.msgmax = 65536
    kernel.msgmnb = 65536
    kernel.msgmni = 32768
    kernel.shmmni = 16384
    kernel.sem = 250 1024000 100 16384
EOF"
    #적용 후 확인
    ssh ${MASTER_HOST} sysctl -p /etc/sysctl.d/42-cp4d.conf && sysctl -a 2>/dev/null | grep kernel.msg | grep -v next_id
    
    for HOST in ${HOSTS}; do  
      ssh ${HOST} "cat << EOF >> /etc/sysctl.d/42-cp4d.conf
      kernel.msgmax = 65536
      kernel.msgmnb = 65536
      kernel.msgmni = 32768
      kernel.shmmni = 16384
      kernel.sem = 250 1024000 100 16384
EOF"
    #적용 후 확인
    ssh ${HOST} sysctl -p /etc/sysctl.d/42-cp4d.conf && sysctl -a 2>/dev/null | grep kernel.msg | grep -v next_id    
    done    
  } 
  
  function setRegistry {
  #이 과정 안하면 registry에 pending걸리는 pod가 있다. 그리고 이것때문에 portworx가 생성이 안됨. 꼭 해줘야하니 다시한번 시행착오 하더라도 해보자
  #master setting
  #https://docs.openshift.com/container-platform/3.11/install_config/registry/securing_and_exposing_registry.html
  oc login https://shin-master.fyre.ibm.com:8443 && docker login -u ocadmin -p $(oc whoami -t) 172.30.135.201:5000
  #nodes setting
  oc get svc/docker-registry
  oc login https://shin-master.fyre.ibm.com:8443 && docker login -u ocadmin -p $(oc whoami -t) 172.30.135.201:5000
  }
  
  function installPortworx {
    scp CP4D_EE_Portworx.bin ${MASTER_HOST}:/root
    ssh ${MASTER_HOST} chmod 755 CP4D_EE_Portworx.bin
    ssh ${MASTER_HOST} ./CP4D_EE_Portworx.bin 
    ssh ${MASTER_HOST} tar zxvf ./ee/cpdv3.0.1_portworx.tgz 
    export token=$(ssh ${MASTER_HOST} oc whoami -t)
    ssh ${MASTER_HOST} ./cpd-portworx/px-images/process-px-images.sh -r docker-registry.default.svc:5000 -u ocadmin -p $token -s kube-system -c docker -d ./imgtemp -t px_2.5.0.1-dist.tgz &&
    ssh ${MASTER_HOST} export USE_SHARED_MDB_DEVICE=yes 
    ssh ${MASTER_HOST} ./cpd-portworx/px-install-3.11/px-install.sh -y -pp Always -R docker-registry.default.svc:5000/kube-system install USE_SHARED_MDB_DEVICE
    ssh ${MASTER_HOST} ./cpd-portworx/px-install-3.11/px-sc.sh
    
    #config nonshared storageclass
    for HOST in ${HOSTS}; do  
       ssh ${HOST} "echo LOCKD_TCPPORT=9023 >> /etc/sysconfig/nfs &&
                    echo LOCKD_UDPPORT=9024 >> /etc/sysconfig/nfs &&
                    echo MOUNTD_PORT=9025 >> /etc/sysconfig/nfs &&
                    echo STATD_PORT=9026 >> /etc/sysconfig/nfs &&
                    systemctl restart nfs-server &&
                    iptables -I INPUT -p tcp -m tcp --match multiport --dports 111,2049,9023,9025,9026 -j ACCEPT &&
                    iptables -I OUTPUT -p tcp -m tcp --match multiport --dports 111,2049,9023,9025,9026 -j ACCEPT &&
                    iptables -I INPUT -p udp -m udp --dport 111 -j ACCEPT &&
                    iptables -I INPUT -p udp -m udp --dport 2049 -j ACCEPT &&
                    iptables -I INPUT -p udp -m udp --dport 9024 -j ACCEPT &&
                    iptables -I OUTPUT -p udp -m udp --dport 111 -j ACCEPT &&
                    iptables -I OUTPUT -p udp -m udp --dport 2049 -j ACCEPT &&
                    iptables -I OUTPUT -p udp -m udp --dport 9024 -j ACCEPT &&
                    iptables-save >/etc/sysconfig/iptables"
        ssh ${HOST} "cat /etc/sysconfig/nfs | grep LOCKD_TCPPORT=9023"
    done  
    #pod들에 에러가 발생하면 각 deployment, pods들을 선택삭제 하고 다시 인스톨 하면 된다(버그)
  }
  
  function installICP4D {
    ssh ${MASTER_HOST} wget https://github.com/IBM/cpd-cli/releases/download/cpd-3.0.1/cloudpak4data-ee-3.0.1.tgz &&
                       tar -xvf cloudpak4data-ee-3.0.1.tgz
    
    
  }
  
  
  
 

  function cpdInstall {
  
    #lite adm
    oc new-project zen &&
    ./cpd-linux adm --repo repo.yaml --assembly lite --arch x86_64 --namespace zen --accept-all-licenses --apply &&
    oc adm policy add-role-to-user cpd-admin-role $(oc whoami) --role-namespace=zen -n zen &&
    oc project zen

#portworx storage class는 gp3는 너무 커서 pvc pending이 생기니까 pg로 
        
     #lite 먼저 설치
    ./cpd-linux \
    --assembly lite \
    --namespace zen \
    --storageclass portworx-shared-gp \
    --transfer-image-to docker-registry-default.apps.jo-master.fyre.ibm.com/zen \
    --repo ./repo.yaml \
    --target-registry-username=$(oc whoami) \
    --target-registry-password=$(oc whoami -t) \
    --insecure-skip-tls-verify \
    --cluster-pull-prefix docker-registry.default.svc:5000/zen \
    --accept-all-licenses --silent-install \
    --override cp-pwx-x86.YAML \
    --verbose
    
    #WD adm 
     ./cpd-linux adm --repo wd-repo.yaml --assembly watson-discovery --arch x86_64 --namespace zen --accept-all-licenses --apply
     
    #wd설치   
    ./cpd-linux \
    --assembly watson-discovery \
    --namespace zen \
    --storageclass portworx-db-gp \
    --transfer-image-to docker-registry-default.apps.jo-master.fyre.ibm.com/zen \
    --repo ./wd-repo.yaml \
    --target-registry-username=$(oc whoami) \
    --target-registry-password=$(oc whoami -t) \
    --insecure-skip-tls-verify \
    --cluster-pull-prefix docker-registry.default.svc:5000/zen \
    --accept-all-licenses --silent-install \
    --override wd-override.yaml \
    --verbose    
  }

#kernelSetting
installPortworx
