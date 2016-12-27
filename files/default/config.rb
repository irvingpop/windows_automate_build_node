current_dir = File.dirname(__FILE__)
eval(IO.read('c:/chef/client.rb'))
log_location STDOUT
node_name "delivery"
client_key "#{current_dir}/delivery_key"
