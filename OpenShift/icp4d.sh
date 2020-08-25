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
    
  # Move install files
  function move {
    scp ./cloudpak4data-ee-3.0.1.tgz ${MASTER_HOST}:/root
    scp CP4D_EE_Portworx.bin ${MASTER_HOST}:/root
  }
  
  # CRI-O container settings  
  function setCrio {
    #파일 맨 앞에 쓰려면 어떻게해야할까? 맨 뒤에 쓰면 데몬셋 에러가 남. 네트워크 설정 위치라서 그렇다. 
    ssh ${MASTER_HOST} "sed -ie 's/# Ansible managed/default_ulimits = [\"nofile=66560:66560\"]/' /etc/crio/crio.conf" &&
                       "sed -ie 's/^pids_limit = 1024/pids_limit = 12288/' /etc/crio/crio.conf" &&
                       systemctl daemon-reload && systemctl restart crio 
    for HOST in ${HOSTS}; do     
      ssh ${HOST} "sed -ie 's/# Ansible managed/default_ulimits = [\"nofile=66560:66560\"]/' /etc/crio/crio.conf" &&
                  "sed -ie 's/^pids_limit = 1024/pids_limit = 12288/' /etc/crio/crio.conf" &&
                  systemctl daemon-reload && systemctl restart crio
    done
}
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
  function installPortworx {
    scp CP4D_EE_Portworx.bin ${MASTER_HOST}:/root
    ssh ${MASTER_HOST} chmod 755 CP4D_EE_Portworx.bin
    ssh ${MASTER_HOST} ./CP4D_EE_Portworx.bin 
    ssh ${MASTER_HOST} tar zxvf ./ee/cpdv3.0.1_portworx.tgz 
    ssh ${MASTER_HOST} ./cpd-portworx/px-images/process-px-images.sh -r docker-registry.default.svc:5000 -c docker -u ocadmin -p $(oc whoami -t) -s kube-system -t px_2.5.0.1-dist.tgz &&
                        export USE_SHARED_MDB_DEVICE=yes &&
                        ./cpd-portworx/px-install-3.11/px-install.sh -y -pp Always -R docker-registry.default.svc:5000/kube-system install &&
                        ./cpd-portworx/px-install-3.11/px-sc.sh
  }
  
  function installICP4D {
    ssh ${MASTER_HOST} wget https://github.com/IBM/cpd-cli/releases/download/cpd-3.0.1/cloudpak4data-ee-3.0.1.tgz &&
                       tar -xvf cloudpak4data-ee-3.0.1.tgz
    
    
  }
  
  
  
  
  
  
  
  //ICP4D 설치파일 받기 깃헙링크
  //portworx 설치파일 받기 IBM SW사이트
  
  #이 과정은 없애야할듯, docker login시 timeout 에러 발생
  function portworx {
   #install
   ./process-px-images.sh -r docker-registry.default.svc:5000 -u ocadmin -p $(oc whoami -t) -c docker -s kube-system -d ./imgtemp -t ./px_2.5.0.1-dist.tgz  
   ./px-install.sh -pp Always -R docker-registry.default.svc:5000/kube-system install USE_SHARED_MDB_DEVICE
  
    #pod들에 에러가 발생하는데 각 deployment, pods들을 선택삭제 하고 다시 인스톨 하면 된다(버그)
   
    #after install portworx, 각 노드에 실행 (마스터에는 하면 Failed to copy modules folder to shared pvc 에러 발생)
    echo LOCKD_TCPPORT=9023 >> /etc/sysconfig/nfs
    echo LOCKD_UDPPORT=9024 >> /etc/sysconfig/nfs
    echo MOUNTD_PORT=9025 >> /etc/sysconfig/nfs
    echo STATD_PORT=9026 >> /etc/sysconfig/nfs
    systemctl restart nfs-server
    iptables -I INPUT -p tcp -m tcp --match multiport --dports 111,2049,9023,9025,9026 -j ACCEPT
    iptables -I OUTPUT -p tcp -m tcp --match multiport --dports 111,2049,9023,9025,9026 -j ACCEPT
    iptables -I INPUT -p udp -m udp --match multiport --dports 111,2049,9024 -j ACCEPT
    iptables -I OUTPUT -p udp -m udp --match multiport --dports 111,2049,9024 -j ACCEPT
    iptables-save >/etc/sysconfig/iptables
    cat /etc/sysconfig/nfs | grep -E '9023|9024|9025|9026' && cat /etc/sysconfig/iptables | grep -E '111,2049'
    #install storage class
     ./px-sc.sh
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
 #ok
 #move 
 
 #to be test
 #call funtions
 #setCrio
 #kernelSetting
 #cpdInstall
