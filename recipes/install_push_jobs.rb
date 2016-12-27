
template 'c:/chef/push-jobs-client.rb' do
  source 'push-jobs-client.rb.erb'
  notifies :restart, 'service[pushy-client]', :delayed
end

execute 'pushy-service-manager-install' do
  command 'pushy-service-manager -a install -c C:\chef\push-jobs-client.rb'
  action :run
end

# pushy-service-manager makes a proper windows service for us, but doesn't start it
service 'pushy-client' do
  action [:enable, :start]
end
