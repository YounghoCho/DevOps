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
    
  # CRI-O container settings  
  function setCrio {
    #왜 폴더를 찾을 수 없다고 하는걸까??
    #그리고 파일 맨 앞에 쓰려면 어떻게해야할까? 맨 뒤에 쓰면 데몬셋 에러가 남. 네트워크 설정 위치라서 그렇다. 
    #ssh ${MASTER_HOST} echo default_ulimits = ["nofile=66560:66560"] >> /etc/crio/crio.conf 
    
    ssh ${MASTER_HOST} "sed -ie 's/^pids_limit = 1024/pids_limit = 12288/' /etc/crio/crio.conf"
    ssh ${MASTER_HOST} systemctl daemon-reload && systemctl restart crio
    for HOST in ${HOSTS}; do     
      ssh ${HOST} "sed -ie 's/^pids_limit = 1024/pids_limit = 12288/' /etc/crio/crio.conf"
      ssh ${HOST} systemctl daemon-reload && systemctl restart crio  
    done
    
    #vi /etc/security/limits.conf 
    #* soft nofile 66560
    #* hard nofile 66560
    #logout
  }
  
  function kernelSetting {
    vi /etc/sysctl.d/42-cp4d.conf
    cat << EOF > /etc/sysctl.d/42-cp4d.conf
    kernel.msgmax = 65536
    kernel.msgmnb = 65536
    kernel.msgmni = 32768
    kernel.shmmni = 16384
    kernel.sem = 250 1024000 100 16384
    EOF
    #적용 후 확인
    sysctl -p /etc/sysctl.d/42-cp4d.conf && sysctl -a 2>/dev/null | grep kernel.msg | grep -v next_id
  }
  
 #call funtions
 setCrio
 kernelSetting
  echo
  echo "ALL DONE"
  echo
