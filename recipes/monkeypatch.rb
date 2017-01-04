# Temporary monkeypatch to ChefDK 1.1.6 until https://github.com/chef/chef/pull/5693 is shipped in a ChefDK

cookbook_file ' C:\opscode\chefdk\embedded\lib\ruby\gems\2.3.0\gems\chef-12.17.44-universal-mingw32\lib\chef\chef_fs\file_system\repository\chef_repository_file_system_root_dir.rb' do
  source 'chef_repository_file_system_root_dir.rb'
end

cookbook_file ' C:\opscode\chefdk\embedded\lib\ruby\gems\2.3.0\gems\chef-12.17.44-universal-mingw32\lib\chef\chef_fs\file_system\repository\nodes_dir.rb' do
  source 'nodes_dir.rb'
end
