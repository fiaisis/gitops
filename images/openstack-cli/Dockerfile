FROM ubuntu:latest

# Install curl and python3-openstackclient
RUN apt-get update
RUN apt-get install curl gpg jq python3-openstackclient python3-octaviaclient -y

# Setup kubectl repository
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
RUN chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
RUN echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
RUN chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Install kubectl + requirements
RUN apt-get update
RUN apt-get install  kubectl apt-transport-https ca-certificates curl gnupg -y
