ARG CUDA=11.4.3
FROM nvidia/cuda:${CUDA}-cudnn8-runtime-ubuntu20.04 as builder

ARG CUDA
#FROM ubuntu:20.04 as builder

# Use bash to support string substitution.
SHELL ["/bin/bash", "-c"]

ENV DOCKERFILE_BASE=ubuntu            \
    DOCKERFILE_DISTRO=ubuntu          \
    DOCKERFILE_DISTRO_VERSION=20.04   \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get -yqq update \
    && apt-get -yqq install --no-install-recommends \
    build-essential \
    ca-certificates \
    cuda-command-line-tools-${CUDA/./-} \
    curl \
    file \
    g++ \
    gcc \
    gfortran \
    git \
    gnupg2 \
    iproute2 \
    locales \
    make \
    python3 \
    python3-pip \
    python3-setuptools \
    tcl \
    unzip \
    libc6-dev \
    libdb-dev \
    patchelf \
    hmmer \
    kalign \
    tzdata \
    wget \
    && locale-gen en_US.UTF-8 \
    && pip3 install boto3 \
    && rm -rf /var/lib/apt/lists/*

ENV LANGUAGE=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8


RUN cd /opt && git clone https://github.com/spack/spack.git -b v0.18.0
COPY scitas-cryoem-spack-packages /opt/scitas-cryoem-spack-packages

COPY buildcache /buildcache

# What we want to install and how we want to install it
# is specified in a manifest file (spack.yaml)
COPY spack.yaml /opt/spack-environment/

RUN cd /opt/spack-environment \
    && /opt/spack/bin/spack -e . buildcache update-index -d /buildcache \
    && /opt/spack/bin/spack -e . buildcache list --allarch

RUN cd /opt/spack-environment \
    && /opt/spack/bin/spack -e . concretize || /bin/true


# Install the software, remove unnecessary deps
RUN cd /opt/spack-environment \
    && /opt/spack/bin/spack -e . concretize \
    && /opt/spack/bin/spack -e . install -j2 --fail-fast --no-check-signature  \
    && /opt/spack/bin/spack -e . gc -y

# ## Strip all the binaries
RUN find -L /opt/view/* -type f -exec readlink -f '{}' \; | \
    xargs file -i | \
    grep 'charset=binary' | \
    grep -v 'nsight-compute' | \
    grep -v 'nsight-systems' | \
    grep -v 'compilers_and_libraries' | \
    grep -v 'targets/x86_64-linux' | \
    grep 'x-executable\|x-archive\|x-sharedlib' | \
    awk -F: '{print $1}' | xargs strip -s || /bin/true

# ## Modifications to the environment that are necessary to run
RUN cd /opt/spack-environment && \
    /opt/spack/bin/spack env activate --sh -d . >> /etc/profile.d/z10_spack_environment.sh

ARG CUDA
# ## Bare OS image to run the installed executables
FROM nvidia/cuda:${CUDA}-cudnn8-runtime-ubuntu20.04
ARG=CUDA

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -yqq update \
    && apt-get -yqq install --no-install-recommends \
    build-essential \
    ca-certificates \
    cuda-command-line-tools-${CUDA/./-} \
    curl \
    file \
    g++ \
    gcc \
    gfortran \
    git \
    locales \
    python3 \
    python3-pip \
    python3-setuptools \
    tzdata \
    wget \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANGUAGE=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8


COPY --from=builder /opt/spack-environment /opt/spack-environment
COPY --from=builder /opt/spack /opt/spack
COPY --from=builder /opt/view /opt/view
COPY --from=builder /etc/profile.d/z10_spack_environment.sh /etc/profile.d/z10_spack_environment.sh

ENTRYPOINT ["/bin/bash", "--rcfile", "/etc/profile", "-l"]
