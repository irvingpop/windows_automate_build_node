# windows_automate_build_node

This cookbook configures a Windows 2012R2 server with ChefDK to become a full Build Node (v1) for Chef Automate.

Unlike previous efforts, this cookbook is 100% standalone and includes no other dependencies, to demonstrate the most simplified Build Node bootstrapping mechanism possible.

## Usage:

It's easiest to download this cookbook to your Chef Automate server and run it from there (same as you would run `automate-ctl install-build-node`). It expects the `/etc/delivery` directory to be populated by a fully functioning Automate server.

Two bash scripts are provided, but it's recommended that you treat them as a reference and modify them to suit your environment:
* `bootstrap-windows-build-node`: Connects to an existing Windows server (via `knife-windows`), bootstraps it with ChefDK and this cookbook in the run_list
* `provision-aws-windows-build-node.sh`: Launches a new Windows server in AWS (via `knife-ec2`), bootstraps it with ChefDK and this cookbook in the run_list (NOTE: you must install a valid `.aws/credentials` file to use this)
