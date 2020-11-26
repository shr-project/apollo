# Copyright (c) 2020 LG Electronics, Inc. All Rights Reserved

# The lgsvl/apollo-5.0 container is huge with almost 10GB size and also needs 4 additional volumes and apollo repository
# after building Apollo inside and including all necessary files inside it becomes approximately 20 GB which is too big
# for use in WISE cloud simulations.

# This runtime image doesn't allow Apollo to be built, but contains all necessary files to just run it.

# The base image itself is quite big:
# lgsvl/apollo-5.0            latest                                         c24e0a4bf5c7        15 months ago       9.83GB
# because it's also based on a big base image:
# apolloauto/apollo           dev-x86_64-20190617_1100                       6b64e2b77e67        15 months ago       9.71GB
# Apollo 6.0 uses intermediate image with just cyber to create the dev container
# apolloauto/apollo           cyber-x86_64-18.04-20200914_0704               7922fa34c210        2 months ago        5.74GB
# apolloauto/apollo           dev-x86_64-18.04-20200914_0742                 e1359ff08479        2 months ago        11.1GB
# Apollo master uses another intermediate image built with base.x86_64.dockerfile:
# apolloauto/apollo           cuda10.2-cudnn7-trt7-devel-18.04-x86_64        f66457a6ec67        2 weeks ago         3.96GB
# apolloauto/apollo           cyber-x86_64-18.04-20200914_0704               7922fa34c210        2 months ago        5.74GB
# apolloauto/apollo           dev-x86_64-18.04-20201110_0617                 062e9ad3e680        2 weeks ago         10.1GB

# Start from nvidia/cuda:8.0-cudnn7-runtime-ubuntu14.04 instead of 8.0-cudnn7-devel-ubuntu14.04 to save 1GB:
# nvidia/cuda                 8.0-cudnn7-devel-ubuntu14.04                   89a0de517837        13 months ago       2.01GB
# nvidia/cuda                 8.0-cudnn7-runtime-ubuntu14.04                 45c714594daa        13 months ago       1.02GB
# Apollo 6.0 uses newer cuda and Ubuntu 18.04 (from cyber image)
# nvidia/cuda                 10.2-cudnn7-devel-ubuntu18.04                  c15c5b31bd86        8 weeks ago         3.82GB
# nvidia/cuda                 10.2-cudnn7-runtime-ubuntu18.04                971911557eb6        8 weeks ago         1.75GB
# Apollo base image is based on either 10.2 (for stable) or 11.1 (for testing with Nvidia Ampere support) nvidia/cuda (see the exact versions in build_apollo_docker.sh), but
# unfortunately in both these cases, the apollo base image is built from IMAGE_IN="nvidia/cuda:${CUDA_LITE}-devel-ubuntu${UBUNTU_LTS}"
# For now use the same runtime image for cuda and we can temporary copy the files from TENSORRT_VERSION=7.0.0 from the built dev container.
FROM nvidia/cuda:10.2-cudnn7-runtime-ubuntu18.04

# docker/build/installers/install_apollo_files.txt explains why these packages are needed
# the order of packages matches with the list there
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install -y \
    --no-install-recommends \
    libx11-6 \
    libgomp1 \
    libopenblas-base \
    libatomic1 \
    python \
    curl \
    libpcap0.8 \
    ocl-icd-libopencl1 \
    libatlas3-base \
    libpython2.7 \
    liblapack3 \
    python3-psutil \
    python-yaml \
    libxcb-shape0 \
    libxcb-xfixes0 \
    && rm -rf /var/lib/apt/lists/*

# nvidia-container-runtime
ENV NVIDIA_VISIBLE_DEVICES ${NVIDIA_VISIBLE_DEVICES:-all}
ENV NVIDIA_DRIVER_CAPABILITIES ${NVIDIA_DRIVER_CAPABILITIES:+$NVIDIA_DRIVER_CAPABILITIES,}graphics

# Run docker/scripts/runtime.x86_64.sh to populate the runtime container with the build of Apollo and the files needed from the mounted volumes.
