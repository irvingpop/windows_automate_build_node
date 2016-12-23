#!/bin/bash -ex
# All of this is to be run from the Automate server or you have copied your /etc/delivery directory to an admin workstation
# Also, assumes you have a ChefDK 0.19.x or later installed

# Step 0, need you to supply the windows hostname, username and password for a preexisting server
# NOTE:  This server must have WinRM enabled and certain permissions set.
#         If in doubt, run https://gist.github.com/vinyar/6735863

usage='
bootstrap-windows-build-node.sh --host hostname_or_ip --username Administrator --password VerySecurePassword
'

if [ $# -lt 3 ]; then
  echo -e $usage
  exit 1
fi


# Argument parsing
while [[ $# -gt 1 ]]
do
key="$1"

case $key in
    -host|--hostname)
    WINDOWS_HOST="$2"
    shift # past argument
    ;;
    -user|--username)
    WINDOWS_USER="$2"
    shift # past argument
    ;;
    --password)
    WINDOWS_PASSWORD="$2"
    shift # past argument
    ;;
    -h|--help)
    echo -e $usage
    exit 0
    ;;
    *)
    echo "Unknown option $1"
    echo -e $usage
    exit 1
    ;;
esac
shift # past argument or value
done

# Step 1, configure a chef/knife client

mkdir .chef

CHEF_SERVER=`grep chef_server /etc/delivery/delivery.rb  | awk '{print $3}'`
CHEF_USERNAME=`grep chef_username /etc/delivery/delivery.rb  | awk '{print $3}'`

cat > .chef/knife.rb <<EOF
node_name ${CHEF_USERNAME}
chef_server_url ${CHEF_SERVER}
client_key "/etc/delivery/delivery.pem"
validation_key "/nonexist" # for validatorless bootstrapping
knife[:aws_credential_file] = File.join(ENV['HOME'], "/.aws/credentials")
#knife[:aws_config_file] = File.join(ENV['HOME'], "/.aws/credentials")
knife[:region] = 'us-west-2'
EOF

eval "$(chef shell-init bash)"
chef gem install knife-windows

# Step 2, bootstrap the windows node

# Verify that `knife wsman` can work successfully before proceeding
# If not, you need to run: https://gist.github.com/vinyar/6735863
knife wsman test $WINDOWS_HOST -m

# For now, use the community push jobs cookbook
cat > ~/Berksfile <<EOF
source 'https://supermarket.chef.io'

metadata
EOF

# Because SSL is hard
mkdir -p ~/.berkshelf
cat > ~/.berkshelf/config.json <<EOF
{
  "ssl": {
    "verify": false
  }
}
EOF

berks install
berks upload

# knife winrm $WINDOWS_HOST "powershell { . { iwr -useb https://omnitruck.chef.io/install.ps1 } | iex; install -project chefdk }" -x $WINDOWS_USER -P $WINDOWS_PASSWORD -m --winrm-shell elevated

# Perform a validatorless bootstrap and install ChefDK all in one pass
DOWNLOAD_URL=`mixlib-install download chefdk --url --platform=windows --platform-version=2008r2 --architecture x86_64 |grep packages.chef.io`
PJ_DOWNLOAD_URL=`mixlib-install download push-jobs-client --url --platform=windows --platform-version=2008r2 --architecture x86_64 |grep packages.chef.io`

# TODO, figure out why we need to grab the push-jobs-client package when it is part of ChefDK, but the push-jobs cookbook can't grok that
cat > ~/wbn-json-attributes.json <<EOF
{
  "push_jobs": {
    "package_url": "${PJ_DOWNLOAD_URL}",
    "package_checksum": "3b979f8d362738c8ac126ace0e80122a4cbc53425d5f8cf9653cdd79eca16d62"
  }
}
EOF
#
# knife bootstrap windows winrm \
# 	$WINDOWS_HOST \
# 	--node-name windows-build-node-1 \
# 	--winrm-user $WINDOWS_USER \
# 	--winrm-password $WINDOWS_PASSWORD \
# 	--msi-url $DOWNLOAD_URL \
# 	--run-list 'recipe[windows_automate_build_node::default]' \
# 	--json-attribute-file ~/wbn-json-attributes.json
#

knife ec2 server create \
  -N windows-build-node-2 \
  -I ami-24e64944 \
  -f t2.medium \
  -x ".\\${WINDOWS_USER}" \
  -P ${WINDOWS_PASSWORD} \
  --ssh-key your-public-key-id \
  --winrm-transport ssl \
  --winrm-ssl-verify-mode verify_none \
  --security-group-ids your-security-groups \
 	--msi-url $DOWNLOAD_URL \
 	--run-list 'recipe[windows_automate_build_node::default]' \
 	--json-attribute-file ~/wbn-json-attributes.json
  -VV
