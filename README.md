# GitOps repository

# Recommended installs for cluster visualisation:
Headlamp (GUI): https://headlamp.dev/

K9s (GUI in CLI): https://k9scli.io/

# Structure:

- apps: Contains the ArgoCD application definitions
- components: Contains custom kubernetes manifests used to define the cluster's components, such as Kafka Clusters, our software and others. 
- projects: Contains the ArgoCD project definitions

Components structure:
```
component_name/
    base/
        thing_to_deploy.yml
        kustomization.yml
    envs/
        staging/
            thing_to_deploy.yml
            kustomization.yml
        prod/
            thing_to_deploy.yml
            kustomization.yml
    variants/
        staging/
            thing_to_deploy.yml
            kustomization.yml
        prod/
            thing_to_deploy.yml
            kustomization.yml
```

- base: The base image, every single version of this component needs these, includes env vars that should be on every deployment.
- envs (previously overlays): This deployment specifics, new env vars, etc. This is where the ArgoCD apps should be aimed at.
- variants: Components that can be used for multiple deployments, usually long-running env vars that can't be promoted to prod. Job creator is a good example of staging and prod having different environment variables required.


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
argocd --port-forward --port-forward-namespace=argocd cluster add staging --yes
```

Add cluster using CLI for prod

```bash
argocd --port-forward --port-forward-namespace=argocd cluster add prod --yes
```

Deploy the app of apps

Reseal all of the secrets for the bitnami sealedsecrets operator in staging and prod then push the changes to Gitops

# How to deploy the app of apps

This will deploy everything using ArgoCD by deploying an application that will deploy everything in the apps folder of this repo.

```bash
kubectl config use-context management
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
kubeseal <secrets.yml>sealedsecrets.yml --namespace fia --controller-name=sealed-secrets-staging --controller-namespace=kube-system --format yaml
```

Setup a local cluster by installing the following
-------------------------------------------------

Run the following from inside the gitops repository with the context set to your local cluster.

```shell
kubectl create namespace rabbitmq
kubectl create namespace fia

helm install ceph-csi-cephfs ceph-csi-charts/ceph-csi-cephfs --namespace fia
helm install rabbitmq-cluster-operator bitnami/rabbitmq-cluster-operator --namespace rabbitmq
helm install csi-driver-smb csi-driver-smb/csi-driver-smb -n kube-system

cd components/fia-api/base
kubectl apply -f fia-api.yml -f fia-api-service.yml -f secrets.yml -n fia
cd ../../..

cd components/rabbitmq/base
kubectl apply -f ha-policy.yml -f permissions.yml -f queues.yml -f rabbitmq-cluster.yml -f secrets.yml -f users.yml -n rabbitmq
cd ../../..

cd components/rundetection/base
kubectl apply -f archive-pvc.yml -f archive-pv.yml -f rundetection.yml -f secrets.yml -n fia
cd ../../..

cd components/archive-secrets/base
kubectl apply -f secrets.yml -n fia
cd ../../..

cd components/ceph/base
kubectl apply -f ceph-configmap.yml -f secrets.yml -n fia
cd ../../..
```

# Deploying to staging using WSL

If you are needing to test changes in a repository without wanting to merge here's how using WSL:

1. Make Changes to the relevant FIAISIS repository.
2. Launch Windows Subsystem for Linux (WSL). Ensure you are using a Bash-compatible shell.
3. Navigate to the relevant repository folder in the terminal.
4. Build the Docker image with `docker build . -t ghcr.io/fiaisis/{repo-name} -f ./container/{repo-name}.D`.
5. Push the image to the GitHub Container Registry `docker push ghcr.io/fiaisis/{repo-name} -a`.
6. A SHA value will be printed to the terminal. Copy this and replace the current one in the relevant `yml` file in your local GitOps repository.
7. Commit the GitOps changes and push to main.
8. Open FIAISIS's management portal and navigate to ARGO CD.
9. Refresh the relevant repository node and the changes should be in effect.
