#!/bin/bash -ex
# All of this is to be run from the Automate server or you have copied your /etc/delivery directory to an admin workstation
# Also, assumes you have a ChefDK 0.19.x or later installed

# Step 0, need you to supply the windows hostname, username and password for a preexisting server
# NOTE:  This server must have WinRM enabled and certain permissions set.
#         If in doubt, run https://gist.github.com/vinyar/6735863
#
# NOTE2:  Due to a weird assumption in the UserData script, the password must be exactly 8 characters long and meet complexity requirements

usage='
provision-aws-windows-build-node.sh --username chef --password Cod3Can! --ssh-key mykey --subnet subnet-ff2f279b --security-group-id sg-4a897632
'

if [ $# -lt 5 ]; then
  echo -e $usage
  exit 1
fi


# Argument parsing
while [[ $# -gt 1 ]]
do
key="$1"

case $key in
    --user|--username)
    WINDOWS_USER="$2"
    shift # past argument
    ;;
    --password)
    WINDOWS_PASSWORD="$2"
    shift # past argument
    ;;
    --ssh-key)
    SSH_KEY="$2"
    shift # past argument
    ;;
    --subnet)
    SUBNET="$2"
    shift # past argument
    ;;
    --security-group-id)
    SECURITY_GROUP_ID="$2"
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

cat > .chef/knife.rb <<EOF
node_name ${CHEF_USERNAME}
chef_server_url ${CHEF_SERVER}
ssl_verify_mode :verify_none
client_key "/etc/delivery/delivery.pem"
validation_key "/nonexist" # for validatorless bootstrapping
knife[:aws_credential_file] = File.join(ENV['HOME'], "/.aws/credentials")
knife[:region] = 'us-west-2'
EOF

# eval "$(chef shell-init bash)"
chef gem install knife-windows
chef gem install knife-ec2

# Step 2, create an automate data_bag_item if one doesn't exist (ala chef-services)
DB_EXISTS=`chef exec knife data bag list automate |grep automate || /bin/true`

if [ -z "${DB_EXISTS}" ]; then
  # Need to use sudo to read the /etc/delivery/builder_key
  # TODO: validate how well this will work if sudo asks you for a password
  sudo chef exec ruby -e 'require "json"; b = {id: "automate", builder_pem: File.read("/etc/delivery/builder_key"), user_pem: File.read("/etc/delivery/delivery.pem") };  File.write("automate.json", JSON.pretty_generate(b))'
  chef exec knife data bag from file automate automate.json
fi

# Step 3, bootstrap the windows node
chef exec berks install
chef exec berks upload -c .berkshelf_config.json

# Perform a validatorless bootstrap and install ChefDK all in one pass
DOWNLOAD_URL=`chef exec mixlib-install download chefdk --url --platform=windows --platform-version=2008r2 --architecture x86_64 |grep packages.chef.io`

# Hack our own user-data file, because knife-ec2's lacks things that we need to revisit later:
#  1. hangs forever if you have a password longer than 8 characters, at a y/n prompt
#  2. doesn't add non-secure winrm port
#  3. need to hack path to install ChefDK upfront
cat > windows-build-node-user-data.txt <<EOF
<powershell>
  #https://gist.github.com/vinyar/6735863

 # below two commands are known to fail for arbitrary reasons
  try { winrm quickconfig -q }
  catch {write-host "winrm quickconfig failed"}
  try { Enable-PSRemoting -force}
  catch {write-host "Enable-PSRemoting -force failed"}

  write-host 'setting up WinRm';
  winrm set winrm/config '@{MaxTimeoutms="1800000"}';
  winrm set winrm/config/client/auth '@{Basic="true"}';            # per https://github.com/WinRb/WinRM
  winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="300"}';
  winrm set winrm/config/service '@{AllowUnencrypted="true"}';     # per https://github.com/WinRb/WinRM
  winrm set winrm/config/service/auth '@{Basic="true"}';           # per https://github.com/WinRb/WinRM

  # needed for windows to manipulate centralized config files which live of a share. Such as AppFabric.
  winrm set winrm/config/service/auth '@{CredSSP="true"}';

  write-host 'Adding custom firewall rule for 5985 and 5986';
  netsh advfirewall firewall add rule name="Windows Remote Management (HTTP-In)" dir=in action=allow enable=yes profile=any protocol=tcp localport=5985 remoteip=any;
  netsh advfirewall firewall add rule name="WinRM HTTPS" protocol=TCP dir=in Localport=5986 remoteport=any action=allow localip=any remoteip=any profile=any enable=yes;

  # Setting up "Known" user for bootstrapping.
  write-host 'setting up secedit rule to disable complex passwords';
  "[System Access]" | out-file c:\delete.cfg;
  "PasswordComplexity = 0" | out-file c:\delete.cfg -append;
  "[Version]"  | out-file c:\delete.cfg -append;
  'signature="$CHICAGO$"'  | out-file c:\delete.cfg -append;

  write-host 'changing secedit policy';
  secedit /configure /db C:\Windows\security\new.sdb /cfg c:\delete.cfg /areas SECURITYPOLICY;

  # TODO: probably need a better escaping system in the future
  write-host 'Setting up "Known" user for bootstrapping.';
  net user /add ${WINDOWS_USER} ${WINDOWS_PASSWORD} /yes;
  write-host 'adding user to admins';
  net localgroup Administrators /add ${WINDOWS_USER};

</powershell>
EOF

chef exec knife ec2 server create \
  -N windows-build-node-2 \
  -I ami-24e64944 \
  -f t2.medium \
  -x ".\\${WINDOWS_USER}" \
  -P ${WINDOWS_PASSWORD} \
  --ssh-key ${SSH_KEY} \
  --winrm-transport ssl \
  --winrm-ssl-verify-mode verify_none \
  --subnet ${SUBNET} \
  --ebs-volume-type gp2 \
  --security-group-id ${SECURITY_GROUP_ID} \
  --msi-url $DOWNLOAD_URL \
  --run-list 'recipe[windows_automate_build_node::default]' \
  --user-data windows-build-node-user-data.txt \
  --bootstrap-template .chef/bootstrap-windows-chefdk-msi.erb
