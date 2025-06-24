# How to add the redpanda CRDs

Need to run this to generate the new version of CRDs for redpanda's operator (be sure to change the version as required):

kubectl kustomize "https://github.com/redpanda-data/redpanda-operator//operator/config/crd?ref=v25.1.1-beta3" > crds.yml

## This section is maintained on behalf of the ISIS Controls team and just handles the routing of this data.