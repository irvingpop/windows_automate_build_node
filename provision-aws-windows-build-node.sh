#!/bin/bash -ex
# All of this is to be run from the Automate server or you have copied your /etc/delivery directory to an admin workstation
# Also, assumes you have a ChefDK 0.19.x or later installed

# Step 0, need you to supply the windows hostname, username and password for a preexisting server
# NOTE:  This server must have WinRM enabled and certain permissions set.
#         If in doubt, run https://gist.github.com/vinyar/6735863
#
# NOTE2:  Due to a weird assumption in the UserData script, the password must be exactly 8 characters long and meet complexity requirements

usage='
bootstrap-windows-build-node.sh --username chef --password Cod3Can! --ssh-key mykey --subnet subnet-ff2f279b --security-group-id sg-be37dec6
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

eval "$(chef shell-init bash)"
chef gem install knife-windows

# Step 2, bootstrap the windows node
berks install
berks upload -c .berkshelf_config.json

# Perform a validatorless bootstrap and install ChefDK all in one pass
DOWNLOAD_URL=`mixlib-install download chefdk --url --platform=windows --platform-version=2008r2 --architecture x86_64 |grep packages.chef.io`
# PJ_DOWNLOAD_URL=`mixlib-install download push-jobs-client --url --platform=windows --platform-version=2008r2 --architecture x86_64 |grep packages.chef.io`

# TODO, figure out why we need to grab the push-jobs-client package when it is part of ChefDK, but the push-jobs cookbook can't grok that
# cat > ~/wbn-json-attributes.json <<EOF
# {
#   "push_jobs": {
#     "package_url": "${PJ_DOWNLOAD_URL}",
#     "package_checksum": "3b979f8d362738c8ac126ace0e80122a4cbc53425d5f8cf9653cdd79eca16d62"
#   }
# }
# EOF

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

  write-host 'Attempting to enable built in 5985 firewall rule';
  netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" profile=public protocol=tcp localport=5985 new remoteip=any;
  write-host 'Adding custom firewall rule for 5985';
  netsh advfirewall firewall add rule name="Opscode-Windows Remote Management (HTTP-In)" dir=in action=allow enable=yes profile=any protocol=tcp localport=5985 remoteip=any;;
  write-host 'adding 80-84 ports for training';
  netsh advfirewall firewall add rule name="Opscode-Windows IIS (HTTP-In)" dir=in action=allow enable=yes profile=any protocol=tcp localport=80-84 remoteip=any;

  # Setting up "Known" user for bootstrapping.
  write-host 'setting up secedit rule to disable complex passwords';
  "[System Access]" | out-file c:\delete.cfg;
  "PasswordComplexity = 0" | out-file c:\delete.cfg -append;
  "[Version]"  | out-file c:\delete.cfg -append;
  'signature="$CHICAGO$"'  | out-file c:\delete.cfg -append;

  write-host 'changing secedit policy';
  secedit /configure /db C:\Windows\security\new.sdb /cfg c:\delete.cfg /areas SECURITYPOLICY;

  write-host 'Setting up "Known" user for bootstrapping.';
  $user="${WINDOWS_USER}";
  $password = "${WINDOWS_PASSWORD}";
  net user /add $user $password /yes;
  write-host 'adding user to admins';
  net localgroup Administrators /add $user;

  write-host 'Adding ChefDK to the system path for future use';
  $oldPath=( Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
  $newPath=$oldPath+';C:\opscode\chefdk\bin\'
  Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH –Value $newPath

</powershell>
EOF

knife ec2 server create \
  -N windows-build-node-2 \
  -I ami-24e64944 \
  -f t2.medium \
  -x ".\\${WINDOWS_USER}" \
  -P ${WINDOWS_PASSWORD} \
  --ssh-key ${SSH_KEY} \
  --winrm-transport ssl \
  --winrm-ssl-verify-mode verify_none \
  --subnet ${SUBNET} \
  --security-group-id ${SECURITY_GROUP_ID} \
 	--msi-url $DOWNLOAD_URL \
  --no-node-verify-api-cert \
 	--run-list 'recipe[windows_automate_build_node::default]' \
 # 	--json-attribute-file ~/wbn-json-attributes.json
  --user-data windows-build-node-user-data.txt
