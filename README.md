# Ops repo for installing aerospike

## Specify the desired topology
- Modify terraform/variables.tf
- Update section *ascluster* and *loadgen* cluster to reflect desired topology

## Install Azure CLI and select subscription
```sh
brew install azure-cli
az login
az account list --output table
az account set --subscription "<SUBSCRIPTION_NAME_FROM_PREV_COMMANDS>"
```
## Steps to create infra and provision Aerospike
```sh
brew install terraform
brew install ansible
terraform init
terraform apply
```
- The SSH keys are stored in terraform/out directory
- Terraform will automatically invoke ansible to provision the nodes accordingly.
- If needed the following commands can be used to trigger anisible manually
```sh
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i ../ansible/inventory.yaml --user aerospike --private-key out/id_rsa_tf ../ansible/aerospike.yaml
ansible-playbook -i ../ansible/inventory.yaml --user aerospike --private-key out/id_rsa_tf ../ansible/amc.yaml
ansible-playbook -i ../ansible/inventory.yaml --user aerospike --private-key out/id_rsa_tf ../ansible/loadgen.yaml
```

## Connect to Aerospike management console
- Setup SSH forwarding (todo: fix access via public DNS name)
```sh
export AMC_HOST=`cat ../ansible/inventory.yaml| grep amc -A 1| tail -n 1`
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -L 8081:localhost:8081 aerospike@$AMC_HOST
```
- Open console in browser - http://localhost:8081
- Enter `localhost` for hostname and hit enter

## SSD prep
*NOTE*: This will wipe all data from the drives. For P40 SSD, this takes around 3 hours to run.
```sh
export ANSIBLE_HOST_KEY_CHECKING=False; ansible-playbook -i ../ansible/inventory.yaml --user aerospike --private-key out/id_rsa_tf ../ansible/ssd-prep.yaml
```

## Run workload to insert test data
```sh
export ANSIBLE_HOST_KEY_CHECKING=False; ansible-playbook -i ../ansible/inventory.yaml --user aerospike --private-key out/id_rsa_tf ../ansible/loadgen-insert.yaml
```
- When running this in parallel using an AS cluster with (5*L48, each with 6*P40 + 6*nvme), this will take about 12 hours.

## Run Read-only workload
```sh
export ANSIBLE_HOST_KEY_CHECKING=False; ansible-playbook -i ../ansible/inventory.yaml --user aerospike --private-key out/id_rsa_tf ../ansible/loadgen-read.yaml
```
- Override thread count by adding --extra-vars "read_thread_count=245"

## Run Read-Modify-Write workload
```sh
export ANSIBLE_HOST_KEY_CHECKING=False; ansible-playbook -i ../ansible/inventory.yaml --user aerospike --private-key out/id_rsa_tf ../ansible/loadgen-rmw.yaml
```

## Run an adhoc command against inventory
```shell script
ansible -i ../ansible/inventory.yaml --user aerospike --private-key out/id_rsa_tf loadgen -a "sudo systemctl stop aerospike"
```

