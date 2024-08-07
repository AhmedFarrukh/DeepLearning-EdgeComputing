:::{.cell}
# Measuring inference time on a Raspberry Pi device
:::

:::{.cell}
The effect of quantization on the inference time of a model is dependent on the hardware environment, amongst other factors. Since quantization can be used to prepare deep learning models for deployment on edge devices, a comparison of the inference time of a model before and after quantization can be useful.

In this notebook, we measure the inference times on a Raspberry Pi 4 with the objective of finding out the effectiveness of quantization in reducing inference time on edge devices.
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
## Transfering code files to the container
:::
:::{.cell}
Later in this notebook, we'll repeatedly run the TFlite benchmark on the models and plot the results. The code file for repeatedly running the benchmark is in [this](https://github.com/AhmedFarrukh/DeepLearning-EdgeComputing/tree/main) git repository, which we need to transfer to the container. 

First, we will clone the repositoy to bring the relevant files onto the chameleon server and then transfer them to the container on our edge device.
:::

:::{.cell .code}
```python
!git clone https://github.com/AhmedFarrukh/DeepLearning-EdgeComputing.git
```
:::

:::{.cell}
Next, we will upload the `code` directory from this repository to the `/root/` directory in the container.
:::

:::{.cell .code}
```python
container.upload(my_container.uuid, "./DeepLearning-EdgeComputing/code", "/root/")
```
:::

:::{.cell}
Finally, we can verify that the files were successfully transferred. The following cell should print the contents of the `code` directory from the repository.
:::

:::{.cell .code}
```python
print(container.execute(my_container.uuid, 'ls -R /root/code')['output'])
```
:::
:::{.cell}
## Downloading files to the container
:::
:::{.cell}
Before we run the experiment, we need to download the models, as well as the TFlite benchmark. 
:::
:::{.cell}
We first install `wget` and `gdown`. `wget` is a utility used to download files from the internet which we will use to downlaod the TFlite benchmark, and `gdown` is a tool to download files specifically from Google Drive, where the models are stored.
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'apt update')
container.execute(my_container.uuid, 'apt -y install wget')
```
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'pip install gdown')
```
:::

:::{.cell}
Next, we can download the TFlite benchmark, storing it in `/root/benchmark` directory. 
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'mkdir /root/benchmark')
container.execute(my_container.uuid,'wget https://storage.googleapis.com/tensorflow-nightly-public/prod/tensorflow/release/lite/tools/nightly/latest/linux_aarch64_benchmark_model -P /root/benchmark')
```
:::

:::{.cell}
The following command should verify that the benchmark was correctly downloaded. We should be able to see a benchmark binary in the `/root/benchmark` directory. 
:::

:::{.cell .code}
```python
print(container.execute(my_container.uuid, 'ls /root/benchmark')['output'])
```
:::

:::{.cell}
We also need to update the permissions of the benchmark binary and allow it to be executed.
:::

:::{.cell .code}
```python
container.execute(my_container.uuid,'chmod +x /root/benchmark/linux_aarch64_benchmark_model')
```
:::

:::{.cell}
All we need now is to download the models themselves. Using `gdown`, the models are downloaded from Google Drive and stored in the `/root/tflite_models` directory.
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'mkdir /root/tflite_models')
container.execute(my_container.uuid, 'gdown --folder https://drive.google.com/drive/folders/1OcJ9ceYg6ZWFJ4QMR0zznsw0KVeHPa4h -O /root/tflite_models')
```
:::
:::{.cell}
The following command should verify that the models were correctly downloaded. In the `/root/tflite_models` directory, we should be able to see two versions of each model: original and quantized. Note that the original models are about four times larger in size than the quantized models.
:::

:::{.cell .code}
```python
print(container.execute(my_container.uuid, 'ls -lR /root/tflite_models')['output'])
```
:::
:::{.cell}
## Running the benchmark
:::
:::{.cell}
We can now run the benchmark on the `tflite` models using the `run_benchmark` file in the `code` directory we transferred to the container earlier. For each model, the `run_benchmark` file runs the benchmark 10 times, storing the output in a file; the file name is the same as the model and the output files are stores in the `/root/results` directory. Once all models have been benchmarked, a file by the name of `completed` is created in the directory. In the next step, we will then parse through these output files, extract the relevant data and create plots.

This step could take about 90 minutes.
:::

:::{.cell .code}
```python
container.execute(my_container.uuid, 'mkdir /root/results')
container.execute(my_container.uuid, 'python /root/code/run_benchmark.py')
```
:::
:::{.cell}
## Plotting the Results
:::
:::{.cell}
Before we plot the results, let's make sure that the python code has finished running. We can read the contents of the `/root/results`. If finished, the directory should contain one file for each model as well as a file named `completed`. If this is not the case, please wait for the code to finish executing.
:::

:::{.cell .code}
```python
print(container.execute(my_container.uuid, 'ls /root/results')['output'])
```
:::

:::{.cell}
We can have a look at one of the files to see what the output of the benchmark looks like.
:::

:::{.cell .code}
```python
print(container.execute(my_container.uuid, 'cat /root/results/MobileNet.txt')['output'])
```
:::
:::{.cell}
Let’s define all the metrics that are reported by the benchmark:
:::

:::{.cell .code}
```python
metrics = ["Init Time (ms)", "Init Inference (ms)", "First Inference (ms)", "Warmup Inference (ms)", "Avg Inference (ms)", "Memory Init (MB)", "Memory Overall (MB)"]
```
:::
:::{.cell}
Since the result of the benchmark is reported as text, we can define a parsing function to extract the data. The parsing function takes the output of the benchmark as an input and adds the results to a dictionary of metrics.
:::

:::{.cell .code}
```python
import re

def parse_benchmark_output(output, results):
    """
    Parse benchmark output to extract model initialization times, inference timings, and memory footprint.
    """

    # Regular expressions to match the required information
    init_time_patterns = [
        re.compile(r'INFO: Initialized session in (\d+.\d+)ms.'),
        re.compile(r'INFO: Initialized session in (\d+)ms.')
    ]
    inference_patterns = [
        re.compile(r'INFO: Inference timings in us: Init: (\d+), First inference: (\d+), Warmup \(avg\): ([\d.e+]+), Inference \(avg\): ([\d.e+]+)'),
        re.compile(r'INFO: Inference timings in us: Init: (\d+), First inference: (\d+), Warmup \(avg\): ([\d.e+]+), Inference \(avg\): (\d+)'),
        re.compile(r'INFO: Inference timings in us: Init: (\d+), First inference: (\d+), Warmup \(avg\): (\d+.\d+), Inference \(avg\): (\d+.\d+)'),
        re.compile(r'INFO: Inference timings in us: Init: (\d+), First inference: (\d+), Warmup \(avg\): (\d+), Inference \(avg\): (\d+.\d+)'),
        re.compile(r'INFO: Inference timings in us: Init: (\d+), First inference: (\d+), Warmup \(avg\): (\d+), Inference \(avg\): (\d+)'),
    ]
    memory_patterns = [
        re.compile(r'INFO: Memory footprint delta from the start of the tool \(MB\): init=(\d+.\d+) overall=(\d+.\d+)'),
        re.compile(r'INFO: Memory footprint delta from the start of the tool \(MB\): init=(\d+.\d+) overall=(\d+)'),
        re.compile(r'INFO: Memory footprint delta from the start of the tool \(MB\): init=(\d+) overall=(\d+.\d+)'),
        re.compile(r'INFO: Memory footprint delta from the start of the tool \(MB\): init=(\d+) overall=(\d+)'),
    ]
    for line in output.split('\n'):
        # Match the initialization time
        for pattern in init_time_patterns:
            init_match = pattern.search(line)
            if init_match:
                results['Init Time (ms)'].append(float(init_match.group(1)))
                break

        # Match the inference timings
        for pattern in inference_patterns:
            inference_match = pattern.search(line)
            if inference_match:
                results["Init Inference (ms)"].append(int(inference_match.group(1))/1000)
                results["First Inference (ms)"].append(int(inference_match.group(2))/1000)
                results["Warmup Inference (ms)"].append(float(inference_match.group(3))/1000)
                results["Avg Inference (ms)"].append(float(inference_match.group(4))/1000)
                break

        # Match the memory footprint
        for pattern in memory_patterns:
            memory_match = pattern.search(line)
            if memory_match:
              results['Memory Init (MB)'].append(float(memory_match.group(1)))
              results['Memory Overall (MB)'].append(float(memory_match.group(2)))
              break

```
:::
:::{.cell}
Next, we can define a Pandas Dataframe to store our results. Since we will be repeatedly running the benchmark to estimate the standard deviation of results as well, for each metric, we will define two columns - one for the mean and the other for the standard deviation.
:::

:::{.cell .code}
```python
import pandas as pd

# Define model types (rows)
rows = []
for model in modelNames:
  rows.append(model)
  rows.append(model + "_quant")

# Define columns
cols = []
for metric in metrics:
  cols.append(metric)
  cols.append(metric + "_sd")

# Create an empty DataFrame
finalResult = pd.DataFrame(index=rows, columns=cols)
```
:::
:::{.cell}
Finally, we can use the functions and structures defined above to parse through the data and populate the dataframe with relevant metrics.
:::

:::{.cell .code}
```python
import subprocess
from collections import defaultdict
from statistics import mean
from statistics import stdev

n = 10 #the number of times the benchmark is called for each model

for modelName in rows:
  print(modelName)
  modelResults = defaultdict(list)
  outputOriginal = print(container.execute(my_container.uuid, 'cat /root/results/' + modelName + '.txt')['output'])
  output = parse_benchmark_output(outputOriginal, modelResults)

  for metric in metrics:
    finalResult.loc[modelName, metric] = mean(modelResults[metric])
    finalResult.loc[modelName, metric + "_sd"] = stdev(modelResults[metric])
```
:::

:::{.cell}
Let’s have a look at the results.
:::

:::{.cell .code}
```python
print(finalResult)
```
:::
:::{.cell}
Let’s create a directory to store the plots from our data:
:::

:::{.cell .code}
```python
!mkdir ./plots
```
:::
:::{.cell}
Finally, we can generate plots of the results.
:::

:::{.cell .code}
```python
import matplotlib.pyplot as plt
import numpy as np
for metric in metrics:
    means_orig = finalResult.loc[modelNames, metric].values
    errors_orig = finalResult.loc[modelNames, metric + "_sd"].values
    means_quant = finalResult.loc[[model + "_quant" for model in modelNames], metric].values
    errors_quant = finalResult.loc[[model + "_quant" for model in modelNames], metric + "_sd"].values


    n_groups = len(modelNames)
    index = np.arange(n_groups)

    fig, ax = plt.subplots()
    bar_width = 0.35
    opacity = 0.8

    rects1 = plt.bar(index, means_orig, bar_width,
                     alpha=opacity,
                     yerr=errors_orig,
                     label='Original')

    rects2 = plt.bar(index + bar_width, means_quant, bar_width,
                     alpha=opacity,
                     yerr=errors_quant,
                     label='Quantized')

    plt.xlabel('Model')
    plt.ylabel(metric)
    plt.title(f'Bar Chart for {metric}')
    plt.xticks(index + bar_width / 2, modelNames, rotation=45)
    plt.legend()

    plt.tight_layout()

    # Save the plot as an image
    plt.savefig("./plots" + metric + "_bar_chart.png")

    # Show the plot
    plt.show()
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
Run the following cell to delete the lease as well.
:::

:::{.cell .code}
```python
DELETE = False #Default value is False to prevent any accidental deletes. Change it to True for deleting the resources

if DELETE:

    # delete lease
    chi.lease.delete_lease(lease["id"])
```
:::