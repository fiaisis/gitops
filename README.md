# GitOps repository

# Structure:

- apps: Contains the ArgoCD application definitions
- components: Contains custom kubernetes manifests used to define the cluster's components, such as Kafka Clusters, our software and others. 
- projects: Contains the ArgoCD project definitions

# Summary:

The app of apps will deploy changes of the CRDs to the ArgoCD cluster automatically, the only thing that needs to be manually applied is that app of apps CRD.

The life of a deployed application:
    - Written by developer
    - It is deployed to staging
    - Once tested on staging, it is deployed to production.

TL;DR Overlays from kustomize determine where changes are deployed to and patch the base version that is deployed to "all"

# Setup:

Add repository in the UI

Login to the CLI:

```bash
argocd --port-forward --port-forward-namespace=argocd login --username=admin --password="MY_PASSWORD"
```

Add cluster using CLI for staging:

```bash
argocd --port-forward --port-forward-namespace=argocd cluster add k0s-cluster-staging --yes
```

Add cluster using CLI for prod

```bash
argocd --port-forward --port-forward-namespace=argocd cluster add k0s-cluster --yes
```

Deploy the app of apps

Reseal all of the secrets for the bitnami sealedsecrets operator in staging and prod then push the changes to Gitops

Go into Memphis and setup the required user using UI

# How to deploy the app of apps

This will deploy everything using ArgoCD by deploying an application that will deploy everything in the apps folder of this repo.

```bash
kubectl config use-context k0s-cluster-ci-cd
kubectl apply -f apps/app_of_apps/deployment.yml
```

# Deploying to prod and staging

Use the correct overlays for deploying patches the base image that are deployed. The overlay patching is performed by https://kustomize.io/

# Adding a new secret

Requires you to install kubeseal:

e.g.
```shell
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.22.0/kubeseal-0.22.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.22.0-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

Ensure that the secret file (Using bitnami sealedsecrets) exists in the correct folder for it's deployment, so that it is deployed alongside the application it is needed for.

To seal a secret so it can be deployed (replace staging with nothing in the --controller-name arg):

```shell
kubeseal <secrets.yml>sealedsecrets.yml --namespace ir --controller-name=sealed-secrets-staging --controller-namespace=kube-system --format yaml
```
