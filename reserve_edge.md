:::{.cell}
# Running a Single User Notebook Server on a Raspberry Pi device
:::

:::{.cell}
This notebook describes how to run a single user Jupyter notebook server on a Raspberry Pi device using Chameleon. This would allow us to run our experiment on a Raspberry Pi 4 device. 
:::

:::{.cell}
## Reservation
:::

:::{.cell .code}
```python
import chi, os, time
from chi import lease
from chi import server
from chi import container

PROJECT_NAME = os.getenv('OS_PROJECT_NAME') # change this if you need to
chi.use_site("CHI@Edge")
chi.set("project_name", PROJECT_NAME)
username = os.getenv('USER') # all exp resources will have this prefix
```
:::

:::{.cell .code}
```python
NODE_TYPE = 'raspberrypi4-64'
expname = "edge-cpu"
```
:::

:::{.cell .code}
```python
res = []
lease.add_device_reservation(res, machine_name=NODE_TYPE, count=1)

start_date, end_date = lease.lease_duration(days=0, hours=10)
# if you won't start right now - comment the line above, uncomment two lines below
# start_date = '2024-04-02 15:24' # manually define to desired start time
# end_date = '2024-04-03 01:00' # manually define to desired start time

l = lease.create_lease(f"{username}-{NODE_TYPE}", res, start_date=start_date, end_date=end_date)
l = lease.wait_for_active(l["id"])  #Comment this line if the lease starts in the future
```
:::

:::{.cell .code}
```python
# continue here, whether using a lease created just now or one created earlier
l = lease.get_lease(f"{username}-{NODE_TYPE}")
lease_id = l['id']
```
:::

:::{.cell}
## Launching a Container
:::

:::{.cell}
Now, we are ready to launch a container!

-   **Container** : A container is like a logical “box” that holds
    everything needed to run an application. It includes the application
    itself, along with all the necessary prerequisite software, files,
    and settings it needs to work properly.
-   **Image** : An image is like a pre-packaged “starting point” for a
    container. On CHI@Edge, we can use any image that is built for the
    ARM64 architecture - e.g. anything on [this
    list](https://hub.docker.com/search?type=image&architecture=arm64&q=).
    In this example, we’re going to run a machine learning application
    written in Python, so we will use the `python:3.9-slim` image as a
    starting point for our container. This is a lightweight installation
    of the Debian Linux operating system with Python pre-installed.

When we create the container, we could also specify some additional
arguments:

-   `workdir`: the “working directory” - location in the container’s
    filesystem from which any commands we specify will run.
-   `exposed_ports`: if we run any applications inside the container
    that need to accept incoming requests from a network, we will need
    to export a “port” number for those incoming requests. Any requests
    to that port number will be forwarded to this container.
-   `command`: if we want to execute a specific command immediately on
    starting the container, we can specify that as well.

For this particular experiment, we’ll specify that port 22 - which is
used for SSH access - should be exposed.

Also, since we do not specify a `command` to run, we will further
specify `interactive = True` - that it should open an interactive Python
session - otherwise the container will immediately stop after it is
started, because it has no “work” to do.

First, we’ll specify the name for our container - we’ll include our
username and the experiment name in the container name, so that it will
be easy to identify our container in the CHI@Edge web interface.
:::

:::{.cell .code}
```python
# set a name for the container
# Note that underscore characters _ are not allowed - we replace each _ with a -
container_name = f"{username}-{expname}".replace("_","-")
```
:::

:::{.cell}
Then, we can create the container!
:::

:::{.cell .code}
```python
try:
    my_container = container.create_container(
        container_name,
        image="python:3.9-slim",
        reservation_id=lease.get_device_reservation(lease_id),
        interactive=True,
        exposed_ports=[22],
        platform_version=2,
    )
except RuntimeError as ex:
    print(ex)
    print(f"Please stop and/or delete {container_name} and try again")
else:
    print(f"Successfully created container: {container_name}!")
```
:::

:::{.cell}
The next cell waits for the container to be active - when it is, it will
print some output related to the container state.
:::

:::{.cell .code}
```python
# wait until container is ready to use
container.wait_for_active(my_container.uuid)
```
:::

:::{.cell}
Once the container is created, you should be able to see it and monitor
its status on the [CHI@Edge web
interface](https://chi.edge.chameleoncloud.org/project/container/containers).
(If there was any problem while creating the container, you can also
delete the container from that interface, in order to be able to try
again.)
:::

:::{.cell}
## Attach an Address and set up SSH
:::
:::{.cell}
Just as with a conventional “server” on Chameleon, we can attach an
address to our container, then use SSH to access its terminal.

First, we’ll attach an address:
:::

:::{.cell .code}
```python
public_ip = container.associate_floating_ip(my_container.uuid)
```
:::

:::{.cell}
Then, we need to install an SSH server on the container - it is not
pre-installed on the image we selected. We can use the
`container.execute()` function to run commands inside the container, in
order to install the SSH server.
:::
:::{.cell .code}
```python
container.execute(my_container.uuid, 'apt update')
container.execute(my_container.uuid, 'apt -y install openssh-server')
```
:::
:::{.cell}
There is one more necessary step before we can access the container over
SSH - we need to make sure our key is installed on the container. Here,
we will upload the key from the Jupyter environment, and make sure it is
configured with the appropriate file permissions:
:::
:::{.cell .code}
```python
!mkdir -p tmp_keys
!cp /work/.ssh/id_rsa.pub tmp_keys/authorized_keys
```
:::
:::{.cell .code}
```python
container.execute(my_container.uuid, 'mkdir -p /root/.ssh')
container.upload(my_container.uuid, "./tmp_keys/authorized_keys", "/root/.ssh")
container.execute(my_container.uuid, 'chown root /root/.ssh')
container.execute(my_container.uuid, 'chown root /root/.ssh/authorized_keys')
container.execute(my_container.uuid, 'chmod go-w /root')
container.execute(my_container.uuid, 'chmod 700 /root/.ssh')
container.execute(my_container.uuid, 'chmod 600 /root/.ssh/authorized_keys')
```
:::
:::{.cell}
Start the SSH server in the container. The following cell should print
“sshd is running”. It it’s not running, it can be an indication that the
SSH server was not fully installed; wait a minute or two and then try
this cell again:
:::
:::{.cell .code}
```python
container.execute(my_container.uuid, 'service ssh start')
container.execute(my_container.uuid, 'service ssh status')
```
:::

:::{.cell}
## Install Required Libraries and Packages
:::
:::{.cell}
The following cells will install the libraries and packages required to initiate the Jupyter notebook server, and then execute the experiment notebook on this server.
:::

:::{.cell}
We will need to install git on our edge container to get access to the experiment notebooks we want to run.
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'apt update')
container.execute(my_container.uuid, 'apt -y install git')
```
:::

:::{.cell}
Next, let's install the python packages and libraries needed to set up the Jupyter server.
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'pip install jupyter-core jupyter-client jupyter -U --force-reinstall --allow-root')
```
:::

:::{.cell}
Let's also install the libraries we need to process the data we generate from benchmarking.
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'pip install matplotlib==3.7.5 gdown==5.2.0 pandas==2.0.3')
```
:::

:::{.cell}
## Retrieve the materials
:::

:::{.cell}
Finally, get a copy of the notebooks that you will run:
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'git clone https://github.com/AhmedFarrukh/DeepLearning-EdgeComputing.git')
```
:::

:::{.cell}
## Run a JupyterHub server
:::

:::{.cell}
Run the following cell:
:::

:::{.cell .code}
```python
print('ssh -L 127.0.0.1:8888:127.0.0.1:8888 root@' + public_ip)
```
:::
then paste its output into a *local* terminal on your own device, to set up a tunnel to the Jupyter server. If your Chameleon key is not in the default location, you should also specify the path to your key as an argument, using `-i`. Leave this SSH session open.

Then, run the following cell, which will start a command that does not terminate:

:::{.cell .code}
```python
container.execute(my_container.uuid, "jupyter notebook --port=8888 --notebook-dir='DeepLearning-EdgeComputing/notebooks'")
```
:::

:::{.cell}
In the output of the cell above, look for a URL in this format:
```
http://localhost:8888/?token=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Copy this URL and open it in a browser. Then, you can run the sequence of notebooks that you'll see there, in order.

If you need to stop and re-start your Jupyter server,

- Use Kernel > Interrupt Kernel *twice* to stop the cell above
- Then run the following cell to kill whatever may be left running in the background.
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'sudo killall jupyter-notebook')
```
:::


:::{.cell}
## Delete the container
:::
:::{.cell}
Lastly, we should stop and delete our container so that others can
create new containers using the same lease. To delete our container, we
can run the following cell:
:::

:::{.cell .code}
```python
container.destroy_container(my_container.uuid)
```
:::
:::{.cell}
Also free up the IP that you we attached to the container, now that it
is no longer in use:
:::
:::{.cell .code}
```python
ip_details = chi.network.get_floating_ip(public_ip)
chi.neutron().delete_floatingip(ip_details["id"])
```
:::
:::{.cell}
Run the following cell to delete the lease as well.
:::

:::{.cell .code}
```python
DELETE = False #Default value is False to prevent any accidental deletes. Change it to True for deleting the resources

if DELETE:

    # delete lease
    chi.lease.delete_lease(l["id"])
```
:::