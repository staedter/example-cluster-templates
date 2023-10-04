## Create Cluster from template

#### Usage

`helm upgrade --install <release-name> </path/to/template-chart-dir> -n fleet-default -f </path/to/override-values>`


#### Example

`helm upgrade --install example-test-cluster ./example-cluster-template -n fleet-default -f ./overrides/example-test-cluster/override.yaml`



___




## Create new cloud provider config token [WORKAROUND: BUG https://github.com/harvester/harvester/issues/4568]

#### General
To setup the permissions to deploy new rke2-guest-vms into a new namespace inside the harvester cluster it is necessary to connect to the harvester cluster and create the new namespace. Afterwards a new cloud-provider-config hast to be created. 

For this use the modified script ./tools/generate_addon_arz.sh and copy the resulting b64 string into your override file. The string is generated as the last lines of the console outoput and also saved into the path ./userdata/namespace/cloud-config-template.b64. It is easier to copy the string from the rendered file. 

**[IMPORTANT]** The harvester kubeconfig needs to use the FQDN of the Harvester VIPs DNS-Record e.g. https://harvester.haa.devops.arz-it.de as the `server` and the correct letsencrypt wildcard CA as the `certificate-authority-data`.

#### Usage
1. export KUBECONFIG~/path/to/harvester-kubeconfig.yaml
2. `./tools/generate_addon_arz.sh <SecretPrefix> <Namespace> <GuestClusterType>`
3. copy base64 userData-String into the key `userData` in the desired override-values.yaml

- SecretPrefix: Name and/or Prefix of multiple CRs that are being created by the script. Use `cloud-provider-config` for consistency.
- Namespace: The namespace inside the harvester cluster where the new VMs will be created. Namespace needs to exist in advance.
- GuestClusterType: At this point `RKE2` is  the only supported GuestClusterType.


#### Example

1. export KUBECONFIG=~/.kube/harvester02-admin.yaml
2. `./tools/generate_addon_arz.sh cloud-provider-config devops RKE2`# example-cluster-templates
# example-cluster-templates
