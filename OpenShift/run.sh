  #!/usr/bin/bash
  ##############################################################
  # You need a VM for provisioning (min 2core 2GBmem 250GBdisk)#
  # In this case, Used Fyre and Z platform Linux 7.7           #
  ##############################################################
  #
  #########################################################################
  # OCP 3.11 auto-provisioning script on Fyre for CPD, WD and EMA only    #
  # Run this Script on VM to deploy Openshift, ICP4D, Watson-Discovery    #
  #########################################################################
  #
  #########################################
  # Contributor.                          #
  # khjang@kr.ibm.com, yhj0306@kr.ibm.com #
  #########################################

  # Setup basic environment variables
  source provision.env

  MASTER_HOST=${FYRE_CLUSTER_PREFIX}-${FYRE_MASTER}	
  echo "fyre_cluster_prefix = " ${FYRE_CLUSTER_PREFIX}
  echo "fyre_master =" ${FYRE_MASTER}	
  for (( i=1 ; i<=${N_WORKER} ; i++ )); do
    HOSTS="${HOSTS} ${FYRE_CLUSTER_PREFIX}-${FYRE_WORKER}-${i}"
  done
  START_TIME=$(date +%Y%m%d%H%M%S)
  mkdir ${START_TIME}
  echo "new directory is " ${START_TIME}
    
  # Get missing password and API key
  # 파일에서 읽어온 패스워드가 없으면 직접 입력받도록 합니다.
  function getCredentials {
    if [ -z ${OS_PASSWORD} ]; then  # -n은 문자열의 길이가 0이면 true
      echo -n Fyre root password: # -n은 syntax error를 체크한다
      read -s OS_PASSWORD # -s는 stdin으로 비밀번호를 입력 받습니다
      echo
    fi
    if [ -z ${FYRE_API_KEY} ]; then
      echo -n Fyre API KEY:
      read -s FYRE_API_KEY
      echo
    fi
    if [ -z ${REDHAT_PASSWORD} ]; then
      echo -n REDHAT password:
      read -s REDHAT_PASSWORD
      echo
    fi
    echo "compelete getCredentials!!!"
  }

  # Make temp directory and build json file to provision VMs
  function setTempDir {
    TEMP_JSON=${START_TIME}/nodes.json
    cp nodes.json ${TEMP_JSON}

    sed -i "s/<FYRE_USERNAME>/${FYRE_USERNAME}/" ${TEMP_JSON} #i는 변경되는 값을 실제 파일에 저장하는 옵션
    sed -i "s/<FYRE_API_KEY>/${FYRE_API_KEY}/" ${TEMP_JSON} #s는 앞에것을 뒤에것으로 치환하는 옵션
    sed -i "s/<FYRE_PRODUCT_GROUP_ID>/${FYRE_PRODUCT_GROUP_ID}/" ${TEMP_JSON}
    sed -i "s/<FYRE_CLUSTER_PREFIX>/${FYRE_CLUSTER_PREFIX}/g" ${TEMP_JSON}
    sed -i "s/<FYRE_SITE>/${FYRE_SITE}/" ${TEMP_JSON}
    sed -i "s/<FYRE_MASTER>/${FYRE_MASTER}/" ${TEMP_JSON} #파일에 기록된 마스터 값을 <FYRE_MASTER>값으로 치환시킨 뒤 TEMP_JSON에 저장한다.
    sed -i "s/<FYRE_WORKER>/${FYRE_WORKER}/" ${TEMP_JSON}
    sed -i "s/<N_WORKER>/${N_WORKER}/" ${TEMP_JSON}

    echo "compelete setTempDir!!!"
  }

  # Start provisioning VMs
  function provisionVMs {
    echo
    echo "### Provisioning VMs"
    # -X는 http method를 지정하게 하는 옵션
    # -s는 응답에서 에러를 보이지 않게 하는 옵션
    # -k는 파일을 요청으로 보내는 옵션(예 : temp_json)
    # @는 파일 경로를 명시하는 옵션 (예 : @/etc/host)
    echo
    BUILD_RESPONSE=$(curl -X POST -ks -u ${FYRE_USERNAME}:${FYRE_API_KEY} \
      'https://api.fyre.ibm.com/rest/v1/?operation=build' --data @${TEMP_JSON})
    #위의 API는 Fyre 사이트에 가면 명시되어있다.
    echo ${BUILD_RESPONSE}
    #BUILD_RESPONSE에서 python을 돌린다. json응답 중 status를 추출한다.
    BUILD_STATUS=$(echo ${BUILD_RESPONSE} | python -c "import sys, json ; print (json.load(sys.stdin)['status'])")
    if [ "${BUILD_STATUS}" == "error" ]; then
      exit 1
    fi

    REQUEST_ID=$(echo ${BUILD_RESPONSE} | python -c "import sys, json ; print (json.load(sys.stdin)['request_id'])")
    echo
    echo "Check provisioning status after 30 seconds"
    echo
    sleep 30
    QUERY_RESPONSE=$(curl -X POST -ks -u ${FYRE_USERNAME}:${FYRE_API_KEY} \
      https://api.fyre.ibm.com/rest/v1/?operation=query\&request=showrequests\&request_id=${REQUEST_ID})
    BUILD_STATUS=$(echo ${QUERY_RESPONSE} | python -c "import sys, json ; print (json.load(sys.stdin)['request'][0]['status'])")
    echo ${QUERY_RESPONSE}
    if [ "${BUILD_STATUS}" == "error" ]; then
      exit 1
    fi

    echo
    echo "Check provisioning status every 1 minute"
    echo
    while [ "${BUILD_STATUS}" != "completed" ]; do
      sleep 60
      QUERY_RESPONSE=$(curl -X POST -ks -u ${FYRE_USERNAME}:${FYRE_API_KEY} \
        https://api.fyre.ibm.com/rest/v1/?operation=query\&request=showrequests\&request_id=${REQUEST_ID})
      echo ${QUERY_RESPONSE}
      BUILD_STATUS=$(echo ${QUERY_RESPONSE} | python -c "import sys, json ; print (json.load(sys.stdin)['request'][0]['status'])")
    done
    echo
    echo "VMs provisioning completed"
    echo
  }

  # Install sshpass
  # sshpass는 noninteractive ssh password provider로 별도의 로그인 과정 없이 파일등에서 읽어서 자동으로 로그인 하는 기능
  function installSSHpass {
    echo
    echo "### Install sshpass"
    echo
    yum install -y sshpass
    echo
  }

  # Setup VMs
  function setupVMs {
    echo
    echo "### Setup VMs"
    echo
    for HOST in ${HOSTS}; do
      echo
      echo "### Setup ${HOST}"
      echo
      sshpass -p ${OS_PASSWORD} ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub ${HOST}
      # LVS 라우터가 실제 서버에 네트워크 패킷을 올바르게 포워딩하기 위해 각각의 LVS 라우터 노드는 커널에서 IP 포워딩을 활성화 시켜야한다
      # LVS는 리눅스 가상 서버
      ssh ${HOST} "sed -ie 's/^net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/sysctl.conf"
      # https://www.kernel.org/doc/Documentation/sysctl/vm.txt 문서에 따르면 max_map_count의 값은 65536으로 되어 있다
      # 일래스틱서치 5에서는 이 값이 너무 작아서. 효율이 떨어지기 때문에 아래처럼 크게 잡아야 한다
      # mmapped 파일에 사용 가능한 충분한 가상 메모리가 있도록 최대 맵 수를 구성해야한다
      # mmap은 파일이나 장치를 메모리에 매핑하는 Unix 시스템 호출
      #vm.max_map_count는 가상메모리 제한이다.
      ssh ${HOST} "echo vm.max_map_count = 262144 >> /etc/sysctl.conf"
      ssh ${HOST} sysctl -p
      scp cyanic1_yum.repo ${HOST}:/etc/yum.repos.d/
      ssh ${HOST} yum repolist
      ssh ${HOST} yum install -y wget git net-tools bind-utils yum-utils iptables-services \
                  bridge-utils bash-completion kexec-tools sos psacct NetworkManager docker-1.13.1 crio
      ssh ${HOST} systemctl start NetworkManager
      ssh ${HOST} systemctl enable NetworkManager
      ssh ${HOST} systemctl start docker
      ssh ${HOST} systemctl enable docker
      ssh ${HOST} yum update -y
      # e는 다중 명령을 쓸 수 있게 하는 옵션
      ssh ${HOST} "sed -ie 's/^SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config"
      ssh ${HOST} touch /.autorelabel
      ssh ${HOST} reboot
      sleep 30
      echo 
    done
      echo
      echo "### Setup ${MASTER_HOST}"
      echo
      sshpass -p ${OS_PASSWORD} ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub ${MASTER_HOST}
      # LVS 라우터가 실제 서버에 네트워크 패킷을 올바르게 포워딩하기 위해 각각의 LVS 라우터 노드는 커널에서 IP 포워딩을 활성화 시켜야한다
      # LVS는 리눅스 가상 서버
      ssh ${MASTER_HOST} "sed -ie 's/^net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/sysctl.conf"
      # https://www.kernel.org/doc/Documentation/sysctl/vm.txt 문서에 따르면 max_map_count의 값은 65536으로 되어 있다
      # 일래스틱서치 5에서는 이 값이 너무 작아서. 효율이 떨어지기 때문에 아래처럼 크게 잡아야 한다
      # mmapped 파일에 사용 가능한 충분한 가상 메모리가 있도록 최대 맵 수를 구성해야한다
      # mmap은 파일이나 장치를 메모리에 매핑하는 Unix 시스템 호출
      #vm.max_map_count는 가상메모리 제한이다.
      ssh ${MASTER_HOST} "echo vm.max_map_count = 262144 >> /etc/sysctl.conf"
      ssh ${MASTER_HOST} sysctl -p
      scp cyanic1_yum.repo ${MASTER_HOST}:/etc/yum.repos.d/
      ssh ${MASTER_HOST} yum repolist
      ssh ${MASTER_HOST} yum install -y wget git net-tools bind-utils yum-utils iptables-services \
                  bridge-utils bash-completion kexec-tools sos psacct NetworkManager docker-1.13.1 crio
      ssh ${MASTER_HOST} systemctl start NetworkManager
      ssh ${MASTER_HOST} systemctl enable NetworkManager
      ssh ${MASTER_HOST} systemctl start docker
      ssh ${MASTER_HOST} systemctl enable docker
      ssh ${MASTER_HOST} yum update -y
      # e는 다중 명령을 쓸 수 있게 하는 옵션
      ssh ${MASTER_HOST} "sed -ie 's/^SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config"
      ssh ${MASTER_HOST} touch /.autorelabel
      ssh ${MASTER_HOST} reboot
      echo 
  }

  # Availability check after reboot
  function checkVMs {
    for HOST in ${HOSTS}; do
      echo
      echo "### Check availability of ${HOST}"
      echo
      READY=1
      # -ne : 값이 다르면 참
      # -eq : 값이 같으면 참
      # $?는 방금 전 실행된 명령의 종료 상태를 1, 0으로 나타낸다
      while [ ${READY} -ne 0 ]; do
        sleep 10
        ssh ${HOST} hostname
        READY=$?
      done
      ssh ${MASTER_HOST} "ssh -o StrictHostKeyChecking=no ${HOST}.fyre.ibm.com hostname"
    done
  }

  # Setup /dev/vdb of master node
  function setupMasterStorage {
    echo
    echo "### Setup /dev/vdb of master node"
    # 대용량 파일시스템 xfs를 사용한다
    # mkfs.xfs는 사용할 디스크를 지정한다
    echo
    ssh ${MASTER_HOST} mkfs.xfs /dev/vdb
    ssh ${MASTER_HOST} mkdir /exports
    ssh ${MASTER_HOST} "echo /dev/vdb /exports xfs defaults 0 0 >> /etc/fstab"
    ssh ${MASTER_HOST} mount /exports
  }

  # Install ansible to master node
  function installAnsible {
    echo
    echo "### Install ansible to master node"
    ssh ${MASTER_HOST} yum install -y openshift-ansible
    echo
  }

  # Make ansible hosts file
  function makeHostsFile {
    TEMP_HOSTS_FILE=${START_TIME}/hosts
    cp hosts ${START_TIME}/hosts
    sed -i "s/<REDHAT_USER>/${REDHAT_USER}/" ${TEMP_HOSTS_FILE}
    sed -i "s/<REDHAT_PASSWORD>/${REDHAT_PASSWORD}/" ${TEMP_HOSTS_FILE}
    sed -i "s/<MASTER>/${FYRE_CLUSTER_PREFIX}-${FYRE_MASTER}/" ${TEMP_HOSTS_FILE}

    echo "[nodes]" >> ${TEMP_HOSTS_FILE}
    # >>는 앞의 내용을 파일로 쓰는 명령어
    echo "${FYRE_CLUSTER_PREFIX}-${FYRE_MASTER}.fyre.ibm.com openshift_node_group_name='node-config-master-infra-crio'" >> ${TEMP_HOSTS_FILE}
    for (( i=1 ; i<=${N_WORKER} ; i++ )); do
      echo "${FYRE_CLUSTER_PREFIX}-${FYRE_WORKER}-${i}.fyre.ibm.com openshift_node_group_name='node-config-compute-crio'" >> ${TEMP_HOSTS_FILE}
    done
    scp ${TEMP_HOSTS_FILE} ${MASTER_HOST}:/etc/ansible/hosts
  }

  # OCP prerequisites run
  function runOCPPrerequisites {
    echo
    echo "### OCP prerequisites start"
    echo
    ssh ${MASTER_HOST} ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml
    if [ $? -ne 0 ]; then
      exit 1
    fi
  }

  # Modify CRIO pids_limit = 8192 -> 12288로 변경(icp4d 3.0.1)
  function modifyCRIOConfig {
    echo
    echo "### Modify CRIO configuration"
    # ICP4D에서는 써야할 프로세스가 1024개가 넘기때문에 증가시켜준다.
    echo
    for HOST in ${HOSTS}; do
      ssh ${HOST} "sed -ie 's/pids_limit = 1024/pids_limit = 12288/' /etc/crio/crio.conf"
      #icp4d때문에 추가했는데 될지모름 0715, 1œㅓㄴ째 줄에 열수있는 문서 수를 추가한다. 확인은 -ulimit -n으로 한다.
      ssh ${HOST} "sed -i '1a\default_ulimits = [ \"nofile=66560:66560\" ]' /etc/crio/crio.conf" 
      ssh ${HOST} systemctl daemon-reload
      ssh ${HOST} systemctl restart crio
    done
  }

  # Run OCP Deployment 오래걸리는 구간
  # master 접근 실패가 나기때문에 이상하지만 master에 직접 들어가서 ansible-playbook을 실행해주자.
  function runOCPDeployment {
    echo 
    echo "### Start OCP deployment"
    echo
    ssh ${MASTER_HOST} ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml
    if [ $? -ne 0 ]; then
      exit 1
    fi
  }

  # Add OCP admin user
  function addOCPAdminUser {
    echo
    echo "### Adding OCP admin user"
    echo
    ssh ${MASTER_HOST} oc login -u system:admin
    ssh ${MASTER_HOST} htpasswd -c -b /etc/origin/master/htpasswd ocadmin ocadmin
    ssh ${MASTER_HOST} oc create user ocadmin
    ssh ${MASTER_HOST} oc create identity htpasswd_auth:ocadmin
    ssh ${MASTER_HOST} oc create useridentitymapping htpasswd_auth:ocadmin ocadmin
    ssh ${MASTER_HOST} oc adm policy add-cluster-role-to-user cluster-admin ocadmin
    ssh ${MASTER_HOST} oc login -u ocadmin -p ocadmin
  }

  # Cleanup temporal files and access
  function cleanUp {
    echo
    echo "### cleanUp temp files and access"
    echo
    rm -Rf ${START_TIME}
    for HOST in ${HOSTS}; do
      scp -q /usr/local/bin/nmon ${HOST}:/usr/local/bin
      ssh ${HOST} "sed -i '/${HOSTNAME}$/d' ~/.ssh/authorized_keys"
    done
  }

  #################################
  ######## MAIN START HERE ########
  #################################
  getCredentials
  setTempDir
  provisionVMs
  installSSHpass
  setupVMs
  checkVMs
  setupMasterStorage
  installAnsible
  makeHostsFile
  runOCPPrerequisites
  modifyCRIOConfig
  runOCPDeployment	
  addOCPAdminUser
  cleanUp

  echo
  echo "-1- OCP Installation All Done"
  echo



  #########################################################################
  # ICP4D 3.0.1 auto-provisioning script on Fyre for CPD, WD only #  
  #########################################################################
  echo
  echo "START Installing ICP4D"
  echo

#  echo ${IBM_KEY}
  
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
#                       echo * soft nofile 66560 >> /etc/security/limits.conf &&
#                       echo * hard nofile 66560 >> /etc/security/limits.conf &&
#                       logout
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
  
 #call funtions
 #setCrio
 #kernelSetting
 #cpdInstall

 
 echo
  echo "ALL DONE"
  echo
    
