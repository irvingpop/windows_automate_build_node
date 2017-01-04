#
# Cookbook Name:: windows_automate_build_node
# Recipe:: default
#
# Copyright (c) 2016 The Authors, All Rights Reserved.

workspace = 'c:/chef/workspace'

delivery_databag = data_bag_item('automate', 'automate')

directory workspace do
  action :create
  recursive true
  user 'chef'
end

%w(.chef bin lib etc).each do |dir|
  directory ::File.join(workspace, dir) do
    user 'chef'
  end
end

%w(etc/builder_key .chef/builder_key).each do |builder_key|
  file ::File.join(workspace, builder_key) do
    content delivery_databag['builder_pem']
    user 'chef'
  end
end

%w(etc/delivery_key .chef/delivery_key etc/delivery.pem).each do |delivery_key|
  file ::File.join(workspace, delivery_key) do
    content delivery_databag['user_pem']
    user 'chef'
  end
end

%w(etc/delivery.rb .chef/knife.rb).each do |knife_config|
  cookbook_file ::File.join(workspace, knife_config) do
    source 'config.rb'
    user 'chef'
  end
end

cookbook_file "#{workspace}/bin/git_ssh" do
  source 'git-ssh-wrapper'
  user 'chef'
end

cookbook_file "#{workspace}/bin/delivery-cmd" do
  source 'delivery-cmd'
  user 'chef'
end

cookbook_file "#{workspace}/bin/delivery-cmd.bat" do
  source 'delivery-cmd.bat'
  user 'chef'
end

# Git on windows will automatically convert LF to CRLF, unless we override that setting
cookbook_file "#{workspace}/.gitconfig" do
  source 'gitconfig'
end

execute 'knife ssl fetch' do
  command "knife ssl fetch -c #{workspace}/.chef/knife.rb"
  action :run
end

execute 'knife ssl fetch automate for client' do
  command "knife ssl fetch -c c:/chef/client.rb -s https://#{node['chef_automate']['fqdn']}"
  action :run
end

execute 'knife ssl fetch automate for workspace' do
  command "knife ssl fetch -c #{workspace}/.chef/knife.rb -s https://#{node['chef_automate']['fqdn']}"
  action :run
end

# Temporary
include_recipe 'windows_automate_build_node::monkeypatch'

include_recipe 'windows_automate_build_node::install_push_jobs'

# Tag this machine as a windows build node and a regular delivery-build-node
tag('windows-build-node')
tag('delivery-build-node')
