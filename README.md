# nanokube

nanokube create's an all-in-one k8s cluster for usage during app development & testing.

The cluster contains a single etcd instance, along with the respective k8s Master & Node components per the installation model.

nanokube intends to provide the user with a local version of a k8s cluster
configured to resemble a production-grade cluster.

**Kudos:** to the [k8s.io](http://k8s.io) community and [CoreOS](http://coreos.com), as this
project draws from k8s' [local-up-cluster.sh](https://github.com/kubernetes/kubernetes/blob/master/hack/local-up-cluster.sh) and [coreos-kubernetes](https://github.com/coreos/coreos-kubernetes)

### Outline

* [System Requirements](#system-requirements)
* [What's Included?](#whats-included)
* [Installation Models](#installation-models)
* [Setup & Use nanokube](#setup--use-nanokube)

### System Requirements

nanokube has only been tested on a system with the following specs:

* Vanilla Ubuntu 16.04
* x86_64 architecture
* 8GB of RAM
* 8 cores
* Docker v1.11.2
* Capable of using `docker run --privileged` (for a Self-Hosted install)
* Capable of reconfiguring Docker networking to use flannel
* 2 network interfaces (PublicNet @ `eth0`, and PrivateNet @ `eth1`)

### What's Included?

* Installed Components
  * etcd
  * flannel
  * Master components (`kube-apiserver`, `kube-controller-manager`, `kube-scheduler`)
  * Node components (`kubelet`, `kube-proxy`)
  * `hyperkube` binary & Docker image
  * `kubectl` CLI
* The ability to choose a particular version of k8s to use
* The option to install an all-in-one k8s cluster using traditional, system-hosted binaries, or the self-hosted k8s model
* Sensible defaults for all k8s Master & Node component configurations
  * These defaults are intended to provide insight into how a k8s cluster should be configured, as well as,
  what addons can & should be added
* TLS for cluster communication using self-signed certs
* Cluster Addons
  * DNS using `kube-dns`

### Installation Models

The two installation models intend to serve as examples for how to
properly configure k8s in a production-like environment.

Either model works, and collectively they showcase different ways to manage the
Kubernetes components that comprise a cluster.

* **Traditional/Binary**

  In this model, the k8s components are delivered using the following artifacts:
  
  * System-Hosted Binaries
      * flannel
      * kube-apiserver
      * kube-controller-manager
      * kube-scheduler
      * kubelet
      * kube-proxy
  * System-Hosted Docker Containers
      * etcd
* **Self-Hosted**

  In this model, the k8s components are delivered using the following artifacts:
  
  * System-Hosted Binaries
      * flannel
  * System-Hosted Docker Containers
      * etcd
      * kubelet (requires privileged mode)
        * The `kubelet` here doubles as the instantiator of both the Self-Hosted
  k8s Pods, and user Pods
  * Self-Hosted k8s Pods (running atop the `kubelet`)
      * kube-apiserver
      * kube-controller-manager
      * kube-scheduler
      * kube-proxy

### Setup & Use nanokube

**1. Install Dependencies**

  * Docker *(Skip this if already installed)*

  ```bash
  curl -sSL https://get.docker.com/ | sh
  ```

  **Note:** Installing Docker with the previous command on a systemd-enabled distro
  requires [this fix](https://github.com/kubernetes/kubernetes-anywhere/blob/master/FIXES.md) to be applied.
  * Misc. Dependencies
  
   ```bash
   ./install_deps.sh
   ```

**2. Configure settings**

  If desired, tweaking the settings of the cluster is possible by altering the variable files in `/vars`.

  If you are unsure about changing the settings, or you simply want to just get k8s up & running, you can skip this step for now.

**3. Choose an installation model**

  Each installation model will start all of the cluster components & sleep until a SIGTERM is sent to `nanokube`.

  * **Traditional/Binary**

    ```bash
    ./nanokube.sh -t
    ```
  * **Self-Hosted**

    ```bash
    ./nanokube.sh -s
    ```

**4. Accessing the k8s Cluster**

Once nanokube has created the cluster, you can begin using k8s through the `kubectl` CLI by either backgrounding the `nanokube` process or opening up a new terminal.

By default in `nanokube`, the k8s Master is configured to advertise itself to the cluster on the `eth1` interface using TLS, however, the
cluster is also accessible on `localhost:8080`; therefore, one can access the cluster in a couple of ways:

* By providing a [kubeconfig file](http://kubernetes.io/docs/user-guide/kubeconfig-file/) specifying the server & creds to `kubectl`, or
* By leveraging defaults in `kubectl` to operate over `localhost:8080`

e.g.

  `kubectl --kubeconfig=/etc/kubernetes/ssl/kubeconfig get pods`

  or

  `kubectl get pods`
  
  The `kubeconfig` isn't required for `nanokube` - it merely is called out here
  to demonstrate an alternate way to access a cluster that may not be on
  `localhost`.

  To access the `nanokube` cluster, simply use `kubectl [command]`. See `kubectl -h` for help.

**5. Verify Cluster Health**

The health of the cluster is reported in `nanokube`, but to verify the components are running we can run a couple of commands ourselves.

#### Verify that the Master is running
```bash
kubectl cluster-info
```

#### Check component statuses

```bash
kubectl get cs
```

#### Check that the Nodes are ready
```bash
kubectl get nodes
```

#### Check that the DNS Pods & Service are running

The pods replicas must all be running and the Service IP must be
assigned.

```bash
kubectl get pods,svc --namespace=kube-system -l k8s-app=kube-dns
```

**6. Run an example**

With an operational cluster, lets test that Kubernetes is working by running the `guestbook` example:

* Create guestbook in k8s

  ```bash
  kubectl create -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/examples/guestbook/all-in-one/guestbook-all-in-one.yaml
  ```
* Check the status of the guestbook creation

  ```bash
  kubectl get pods,svc
  ```

Once all pods are running and the `frontend`, `redis-master` and `redis-slave` all have a Service IP, hit the frontend's Service IP to verify that the guestbook is running

  ```bash
  curl <frontend_service_ip>
  ```

Cleanup

  ```bash
  kubectl delete -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/examples/guestbook/all-in-one/guestbook-all-in-one.yaml
  ```

* Check the status of the guestbook deletion

  ```bash
  kubectl get pods,svc
  ```
