#!/usr/bin/bash
#########################################################################
# OCP 3.11 auto-provisioning script on Fyre for CPD, WD and EMA only    #
#########################################################################

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
function getCredentials {
  if [ -z ${OS_PASSWORD} ]; then
    echo -n Fyre root password:
    read -s OS_PASSWORD
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

  sed -i "s/<FYRE_USERNAME>/${FYRE_USERNAME}/" ${TEMP_JSON}
  sed -i "s/<FYRE_API_KEY>/${FYRE_API_KEY}/" ${TEMP_JSON}
  sed -i "s/<FYRE_PRODUCT_GROUP_ID>/${FYRE_PRODUCT_GROUP_ID}/" ${TEMP_JSON}
  sed -i "s/<FYRE_CLUSTER_PREFIX>/${FYRE_CLUSTER_PREFIX}/g" ${TEMP_JSON}
  sed -i "s/<FYRE_SITE>/${FYRE_SITE}/" ${TEMP_JSON}
  sed -i "s/<FYRE_MASTER>/${FYRE_MASTER}/" ${TEMP_JSON}
  sed -i "s/<FYRE_WORKER>/${FYRE_WORKER}/" ${TEMP_JSON}
  sed -i "s/<N_WORKER>/${N_WORKER}/" ${TEMP_JSON}

  echo "compelete setTempDir!!!"
}

# Start provisioning VMs
function provisionVMs {
  echo
  echo "### Provisioning VMs"
  echo
  BUILD_RESPONSE=$(curl -X POST -ks -u ${FYRE_USERNAME}:${FYRE_API_KEY} \
    'https://api.fyre.ibm.com/rest/v1/?operation=build' --data @${TEMP_JSON})
  echo ${BUILD_RESPONSE}

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
#    sshpass -p Inf0sphere! ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub yh-master
    ssh ${HOST} "sed -ie 's/^net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/sysctl.conf"
#    ssh yh-worker-3 "sed -ie 's/^net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/sysctl.conf"
    ssh ${HOST} "echo vm.max_map_count = 262144 >> /etc/sysctl.conf"
#    ssh yh-master "echo vm.max_map_count = 262144 >> /etc/sysctl.conf"
    ssh ${HOST} sysctl -p
#    ssh ${HOST} rm -f /etc/yum.repos.d/devit-rh7-x86_64.repo
    scp cyanic1_yum.repo ${HOST}:/etc/yum.repos.d/
    ssh ${HOST} yum repolist
    ssh ${HOST} yum install -y wget git net-tools bind-utils yum-utils iptables-services \
                bridge-utils bash-completion kexec-tools sos psacct NetworkManager docker-1.13.1 crio
    ssh ${HOST} systemctl start NetworkManager
    ssh ${HOST} systemctl enable NetworkManager
    ssh ${HOST} systemctl start docker
    ssh ${HOST} systemctl enable docker
    ssh ${HOST} yum update -y
    ssh ${HOST} "sed -ie 's/^SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config"
    ssh ${HOST} touch /.autorelabel
    ssh ${HOST} reboot
    echo 
  done
}

# Availability check after reboot
function checkVMs {
  for HOST in ${HOSTS}; do
    echo
    echo "### Check availability of ${HOST}"
    echo
    READY=1
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
  echo
  ssh ${MASTER_HOST} mkfs.xfs /dev/vdb
  ssh ${MASTER_HOST} mkdir /exports
  ssh ${MASTER_HOST} "echo /dev/vdb /exports xfs defaults 0 0 >> /etc/fstab"
  ssh ${MASTER_HOST} mount /exports
}

# Instrall ansible to master node
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

# Modify CRIO pids_limit = 8192
function modifyCRIOConfig {
  echo
  echo "### Modify CRIO configuration"
  echo
  for HOST in ${HOSTS}; do
    ssh ${HOST} "sed -ie 's/pids_limit = 1024/pids_limit = 8192/' /etc/crio/crio.conf"
    ssh ${HOST} systemctl daemon-reload
    ssh ${HOST} systemctl restart crio
  done
}

# Run OCP Deployment 오래걸리는 구간
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
echo "ALL DONE"
echo
