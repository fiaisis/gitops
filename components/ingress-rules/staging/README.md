# Creating the sealedsecret

Create a htpassword file with:
```shell
htpasswd -c auth user
```
Enter the password


Create secret (this is effectively base encode64'ing it, most convenient way in my opinion)
```shell
kubectl create secret generic basic-auth-test --from-file=auth -n fia 
```

Copy secret to secrets.yml and change name to basic-auth

Then seal it using kubeseal
```shell
kubeseal <secrets.yml>grafana-creds-secret.yml --namespace fia --controller-name=sealed-secrets-staging --controller-namespace=kube-system --format yaml
```