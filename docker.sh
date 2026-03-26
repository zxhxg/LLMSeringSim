#!/bin/bash

# 禁用 Git Bash 路径自动转换（关键！）
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

# 获取 Windows 格式路径
WIN_PWD=$(pwd -W)

# launch docker
docker run --name servingsim_docker \
  -it \
  -v "${WIN_PWD}:/app/LLMServingSim" \
  -w /app/LLMServingSim \
  astrasim/tutorial-micro2024 \
  bash -c "pip3 install pyyaml pyinstrument transformers datasets \
  msgspec scikit-learn xgboost==3.1.2 matplotlib==3.5.3 pandas==1.5.3 \
  numpy==1.23.5 && exec bash"