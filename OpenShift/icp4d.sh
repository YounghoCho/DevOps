  #!/usr/bin/bash
  #########################################################################
  # ICP4D 3.0.1 auto-provisioning script on Fyre for CPD, WD and EMA only #  
  #########################################################################

  # Setup basic environment variables
  source provision.env

  MASTER_HOST=${FYRE_CLUSTER_PREFIX}-${FYRE_MASTER}	
  for (( i=1 ; i<=${N_WORKER} ; i++ )); do
    HOSTS="${HOSTS} ${FYRE_CLUSTER_PREFIX}-${FYRE_WORKER}-${i}"
  done
    
  # desc  
  function test {
  }
 
 #call funtions
 
 
  echo
  echo "ALL DONE"
  echo
