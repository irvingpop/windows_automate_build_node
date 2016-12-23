#
# Cookbook Name:: windows_automate_build_node
# Recipe:: default
#
# Copyright (c) 2016 The Authors, All Rights Reserved.

workspace = 'c:/chef/workspace'

#delivery_databag = data_bag_item('automate', 'automate')

directory workspace do
  action :create
  recursive true
end

%w(.chef bin lib etc).each do |dir|
  directory ::File.join(workspace, dir)
end

%w(etc/builder_key .chef/builder_key).each do |builder_key|
  file ::File.join(workspace, builder_key) do
    content delivery_databag['builder_pem']
    mode 0600
    owner 'root'
    group 'root'
  end
end

%w(etc/delivery_key .chef/delivery_key etc/delivery.pem).each do |delivery_key|
  file ::File.join(workspace, delivery_key) do
    content delivery_databag['user_pem']
  end
end

%w(etc/delivery.rb .chef/knife.rb).each do |knife_config|
  cookbook_file "#{workspace}/#{knife_config}" do
    source 'config.rb'
  end
end

cookbook_file "#{workspace}/bin/git_ssh" do
  source 'git-ssh-wrapper'
end

cookbook_file "#{workspace}/bin/delivery-cmd" do
  source 'delivery-cmd'
end


%W(#{node['chef_server']['fqdn']} #{node['chef_automate']['fqdn']}).each do |server|
  execute "fetch ssl cert for #{server}" do
    command "knife ssl fetch -s https://#{server}"
  end
  execute "fetch ssl cert for #{server}" do
    command "knife ssl fetch -s https://#{server} -c /etc/chef/client.rb"
  end
end

include_recipe 'chef-services::install_push_jobs'
