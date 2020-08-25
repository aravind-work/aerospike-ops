# Ops repo for installing aerospike

## Specify the desired topology
- Modify terraform/variables.tf
- Update section *ascluster* and *loadgen* cluster to reflect desired topology
- Update variable prefix to a different value
- Update ../ansible/configure_aerospike/templates/features.conf.j2. Include the correct signature for the feature file.

## Install Azure CLI and select subscription
```sh
brew install azure-cli
az login
az account list --output table
az account set --subscription "<SUBSCRIPTION_NAME_FROM_PREV_COMMANDS>"
```

## Update terraform/variables.tf file
1. Change the 'prefix' variable to a different value
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
- Open console in browser - http://localhost:8081/#dashboard/localhost:3000/60/

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

## Commands for taking disk snapshots

1. Set the *create_snapshots* variable to *true* in variables.tf file. 
2. Run `terraform apply` - this will create snapshots and create a file with a list of snapshot URLs - ./out/disk-snapshots.txt
3. Set the *create_snapshots* variable to *false* in variables.tf file. 
4. Run `terraform state rm azurerm_snapshot.snapshots` and `terraform state rm local_file.snapshot-locations-file`
5. At this point, we should have the snapshots saved. We will also have removed the snapshot from TF state.

## Commands for restoring from disk snapshots
1.   In the `azurerm_managed_disk` section of main.tf, add the following - 
        `source_resource_id =  split(",", data.template_file.snapshot_urls.rendered)[count.index]`
        `create_option        = "Copy"`
2.  run `terraform apply` - Sometimes terraform hangs on the step to destroy the disk. In this case, manually delete the resources from Azure portal and rerun terraform.
`