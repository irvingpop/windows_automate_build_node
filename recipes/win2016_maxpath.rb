# Recipe to increase MAX_PATH on Windows 2016 servers

registry_key "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Filesystem" do
  values [{
    :name => "LongPathsEnabled",
    :type => :dword,
    :data => 1
  }]
  action :create
  notifies :request_reboot, 'reboot[now]'
end

reboot 'now' do
  action :nothing
  reason 'Need to reboot when the run completes successfully.'
end
