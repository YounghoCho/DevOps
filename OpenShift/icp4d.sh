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
    ssh ${MASTER_HOST} echo default_ulimits = ["nofile=66560:66560"] >> /etc/crio/crio.conf 
    ssh ${MASTER_HOST} "sed -ie 's/^pids_limit = 1024/pids_limit = 12288/' /etc/crio/crio.conf"
  }
 
 #call funtions
 setCrio
 
  echo
  echo "ALL DONE"
  echo
