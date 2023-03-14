# syntax = docker/dockerfile-upstream:master-labs

ARG PYTHON_VERSION=3.8
FROM --platform=${TARGETPLATFORM} python:${PYTHON_VERSION}-slim AS python-base
# Keeps Python from generating .pyc files in the container
ENV PYTHONDONTWRITEBYTECODE 1
# Turns off buffering for easier container logging
ENV PYTHONUNBUFFERED 1
# Don't fall back to legacy build system
ENV PIP_USE_PEP517=1
# Prepare apt for buildkit cache
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
  && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/keep-cache

# Install dependencies
RUN \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update \
  && apt-get install -y \
    --no-install-recommends \
    bash curl wget python3-pip \
    libgl1-mesa-glx=20.3.* \
    libglib2.0-0=2.66.* 

# Install miniconda
ENV CONDA_DIR /opt/conda
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
     /bin/bash ~/miniconda.sh -b -p /opt/conda

# Put conda in path so we can use conda activate
ENV PATH=$CONDA_DIR/bin:$PATH

# Prepare pip for buildkit cache
ARG PIP_CACHE_DIR=/var/cache/buildkit/pip
ENV PIP_CACHE_DIR ${PIP_CACHE_DIR}
RUN mkdir -p ${PIP_CACHE_DIR}

ARG PIP_EXTRA_INDEX_URL
ENV PIP_EXTRA_INDEX_URL ${PIP_EXTRA_INDEX_URL}
ARG PIP_PRE=0
ENV PIP_PRE ${PIP_PRE}

SHELL ["/bin/bash", "-c"]
ADD requirements.txt /app/requirements.txt

WORKDIR /app

# create a new environment
RUN <<EOT
#!/bin/bash
conda init bash
. /root/.bashrc
conda create -n visgpt python=${PYTHON_VERSION}

# activate the new environment
conda activate visgpt

EOT

FROM python-base AS builder
WORKDIR /app
#  prepare the basic environments
RUN --mount=type=cache,target=${PIP_CACHE_DIR} pip wheel --wheel-dir=/wheels -r requirements.txt


FROM python-base
WORKDIR /app
RUN --mount=type=bind,from=builder,source=/wheels,target=/wheels \
    pip install --find-links /wheels -r requirements.txt
RUN conda install pytorch torchvision torchaudio pytorch-cuda=11.7 -c pytorch-nightly -c nvidia
ADD --link . /app/
EXPOSE 7868
ENV OPENAI_API_KEY=""
VOLUME /root/.cache
CMD python visual_chatgpt.py --load "ImageEditing_cuda:0,Text2Image_cuda:0,InstructPix2Pix_cpu,ImageCaptioning_cpu"
