# ---------------------------------------------------------------------------- #
#                         Stage 1: Download the models                         #
# ---------------------------------------------------------------------------- #
FROM alpine/git:2.36.2 as download

# COPY builder/clone.sh /clone.sh

# Clone the repos and clean unnecessary files
# RUN . /clone.sh taming-transformers https://github.com/CompVis/taming-transformers.git 24268930bf1dce879235a7fddd0b2355b84d7ea6 && \
#     rm -rf data assets **/*.ipynb

# RUN . /clone.sh stable-diffusion-stability-ai https://github.com/Stability-AI/stablediffusion.git 47b6b607fdd31875c9279cd2f4f16b92e4ea958e stable-diffusion-stability-ai && \
#     rm -rf assets data/**/*.png data/**/*.jpg data/**/*.gif

# RUN . /clone.sh CodeFormer https://github.com/sczhou/CodeFormer.git c5b4593074ba6214284d6acd5f1719b6c5d739af && \
#     rm -rf assets inputs

# RUN . /clone.sh BLIP https://github.com/salesforce/BLIP.git 48211a1594f1321b00f14c9f7a5b4813144b2fb9 && \
#     . /clone.sh k-diffusion https://github.com/crowsonkb/k-diffusion.git c9fe758 && \
#     . /clone.sh clip-interrogator https://github.com/pharmapsychotic/clip-interrogator 2486589f24165c8e3b303f84e9dbbea318df83e8

RUN wget -O /model.safetensors https://civitai.com/api/download/models/15236


# ---------------------------------------------------------------------------- #
#                        Stage 2: Setup deps                                   #
# ---------------------------------------------------------------------------- #
FROM python:3.10.9-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    LD_PRELOAD=libtcmalloc.so \
    ROOT=/stable-diffusion-webui \
    PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt install -y \
    fonts-dejavu-core rsync git jq moreutils aria2 wget libgoogle-perftools-dev procps && \
    apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && apt-get clean -y

RUN --mount=type=cache,target=/cache --mount=type=cache,target=/root/.cache/pip \
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

RUN --mount=type=cache,target=/cache --mount=type=cache,target=/root/.cache/pip \
    apt-get update && apt-get install ffmpeg libsm6 libxext6 python3-opencv  -y && \
    pip install opencv-python

RUN --mount=type=cache,target=/root/.cache/pip \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git && \
    cd stable-diffusion-webui && \
    git reset --hard f865d3e1 && \ 
    pip install -r requirements_versions.txt


#COPY --from=download /repositories/ ${ROOT}/repositories/
COPY --from=download /model.safetensors /model.safetensors
#RUN mkdir ${ROOT}/interrogate && cp ${ROOT}/repositories/clip-interrogator/data/* ${ROOT}/interrogate
#RUN --mount=type=cache,target=/root/.cache/pip \
#    pip install -r ${ROOT}/repositories/CodeFormer/requirements.txt

# Install Python dependencies (Worker Template)
COPY builder/requirements.txt /requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip && \
    pip install --upgrade -r /requirements.txt --no-cache-dir && \
    rm /requirements.txt

#ARG SHA=89f9faa63388756314e8a1d96cf86bf5e0663045
RUN --mount=type=cache,target=/root/.cache/pip \
    cd stable-diffusion-webui && \
    git fetch && \
    #git reset --hard <TODO: lock to confirmed good hash> && \ 
    pip install -r requirements.txt

ADD src .

# Install extensions
RUN --mount=type=cache,target=/root/.cache/pip \
    cd stable-diffusion-webui/extensions && \
    git clone https://github.com/Mikubill/sd-webui-controlnet.git && \
    #git reset --hard <TODO: lock to confirmed good hash> && \ 
    pip install -r sd-webui-controlnet/requirements.txt

RUN --mount=type=cache,target=/root/.cache/pip \
    cd stable-diffusion-webui/extensions && \
    git clone https://github.com/rewbs/deforum-for-automatic1111-webui.git deforum && \
    #git reset --hard <TODO: lock to confirmed good hash> && \ 
    pip install -r deforum/requirements.txt

# Installing requirements by running launcher, but with --exit flag so that webui isn't started.
RUN --mount=type=cache,target=/root/.cache/pip \
    cd stable-diffusion-webui && python ./launch.py --skip-torch-cuda-test  --exit

# Force one of the models to be downloaded by running a subset of the UI?
# TODO we might need this for other things like depth models etc...
COPY builder/cache.py /stable-diffusion-webui/cache.py
RUN --mount=type=cache,target=/root/.cache/pip \
    cd stable-diffusion-webui && python cache.py --use-cpu=all --ckpt /model.safetensors

# Cleanup section (Worker Template)
RUN apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

RUN chmod +x /start.sh
CMD /start.sh
