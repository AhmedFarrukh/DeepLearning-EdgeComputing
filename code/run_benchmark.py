import subprocess
modelNames = ["MobileNet", "InceptionV3", "ResNet50", "ResNet101" , "ResNet152", "VGG16", "VGG19"]


numModels = len(modelNames)
for i in range(numModels):
  modelNames.append(modelNames[i] + "_quant")

for modelName in modelNames:
    file = open(f'/root/results/{modelName}.txt', "w")
    for i in range(10):
        outputOriginal = subprocess.check_output("/root/benchmark/linux_aarch64_benchmark_model \
            --graph=/root/tflite_models/" + modelName +".tflite"+" \
            --num_threads=1", shell=True)
        outputOriginal = outputOriginal.decode('utf-8')
        file.write(modelName + '\n')
        file.write(outputOriginal)
        file.write("\n")
    file.close()

file = open("/root/results/completed.txt", "w")
file.write("Benchmarking Completed!")
file.close()