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
    --host|--hostname)
    WINDOWS_HOST="$2"
    shift # past argument
    ;;
    --user|--username)
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
CHEF_SERVER=`grep chef_server /etc/delivery/delivery.rb  | awk '{print $3}'`
CHEF_USERNAME=`grep chef_username /etc/delivery/delivery.rb  | awk '{print $3}'`
CHEF_SERVER_FQDN=`echo ${CHEF_SERVER} | awk -F/ '{print $3}'`
AUTOMATE_SERVER_FQDN=`grep delivery_fqdn /etc/delivery/delivery.rb | awk '{print $2}' | tr -d '""'`


cat > .chef/knife.rb <<EOF
node_name ${CHEF_USERNAME}
chef_server_url ${CHEF_SERVER}
ssl_verify_mode :verify_none
client_key "/etc/delivery/delivery.pem"
validation_key "/nonexist" # for validatorless bootstrapping
EOF

chef gem install knife-windows

# Step 2, create an automate data_bag_item if one doesn't exist (ala chef-services)
DB_EXISTS=`chef exec knife data bag list automate |grep automate || /bin/true`

if [ -z "${DB_EXISTS}" ]; then
  # Need to use sudo to read the /etc/delivery/builder_key
  # TODO: validate how well this will work if sudo asks you for a password
  sudo chef exec ruby -e 'require "json"; b = {id: "automate", builder_pem: File.read("/etc/delivery/builder_key"), user_pem: File.read("/etc/delivery/delivery.pem") };  File.write("automate.json", JSON.pretty_generate(b))'
  chef exec knife data bag from file automate automate.json
fi

# Step 3, bootstrap the windows node

# Verify that `knife wsman` can work successfully before proceeding
# If not, you need to run: https://gist.github.com/vinyar/6735863
chef exec knife wsman test $WINDOWS_HOST -m

chef exec berks install
chef exec berks upload -c .berkshelf_config.json

# Perform a validatorless bootstrap and install ChefDK all in one pass
DOWNLOAD_URL=`chef exec mixlib-install download chefdk --url --platform=windows --platform-version=2008r2 --architecture x86_64 |grep packages.chef.io`

# To deliver the chef server and automate fqdn's in a fashion also compatible with chef-services
cat > ~/wbn-json-attributes.json <<EOF
{
  "chef_automate": {
    "fqdn": "${AUTOMATE_SERVER_FQDN}"
  },
  "chef_server": {
    "fqdn": "${CHEF_SERVER_FQDN}"
  }
}
EOF

chef exec knife bootstrap windows winrm \
  $WINDOWS_HOST \
  --node-name windows-build-node-1 \
  --winrm-user $WINDOWS_USER \
  --winrm-password $WINDOWS_PASSWORD \
  --msi-url $DOWNLOAD_URL \
  --run-list 'recipe[windows_automate_build_node::default]' \
  --bootstrap-template .chef/bootstrap-windows-chefdk-msi.erb \
  --json-attribute-file ~/wbn-json-attributes.json
