# Waymo 下载、预处理与接入 VINGS 操作手册

## 1. 目标

本手册用于完成以下任务：

- 下载 Waymo Open Dataset 原始 `.tfrecord`
- 使用 NeuralSim 预处理 Waymo 数据
- 生成 VINGS 可直接读取的 `color/*.jpg`
- 配置并运行 VINGS 的 Waymo `vo` 模式

## 2. 适用范围

- 数据集：Waymo Open Dataset Perception v1.x training split
- 场景：室外驾驶
- 模式：VINGS `vo`

## 3. 仓库与环境

### 3.1 仓库

- `VINGS-Mono`：最终运行 SLAM
- `NeuralSim`：下载与预处理 Waymo
- `nr3d_lib`：NeuralSim 的 submodule

### 3.2 环境

- `vings`：运行 VINGS
- `waymo-prep`：下载 Waymo、运行 NeuralSim 预处理

要求：

- 不在 `vings` 中安装 Waymo 预处理依赖
- 不在 `waymo-prep` 中安装 VINGS 运行依赖

## 4. 最终数据格式

VINGS 当前 Waymo 数据读取格式为：

```text
<dataset.root>/
└── color/
    ├── 00000000.jpg
    ├── 00000001.jpg
    └── ...
```

## 5. 前置条件

执行前完成以下操作：

1. 接受 Waymo 数据协议：[https://waymo.com/open/](https://waymo.com/open/)
2. 安装 `gcloud` 与 `gsutil`
3. 执行 Google 登录：

```bash
gcloud auth login
```

## 6. 目录规划

建议使用以下路径：

```bash
export NS=/home/dzp62442/Projects/neuralsim
export RAW=/home/B_UserData/dongzhipeng/Datasets/waymo_neuralsim/raw
export PROC=/home/B_UserData/dongzhipeng/Datasets/waymo_neuralsim/processed
export VINGS_DATA=datasets/waymo/
export SCENE_ID=segment-1172406780360799916_1660_000_1680_000_with_camera_labels
```

说明：

- `NS`：NeuralSim 根目录
- `RAW`：Waymo 原始 `.tfrecord` 目录
- `PROC`：NeuralSim 预处理输出目录
- `VINGS_DATA`：VINGS 最终读取目录
- `SCENE_ID`：单个 Waymo 场景名

## 7. 获取 NeuralSim

### 7.1 克隆仓库

```bash
git clone --recursive https://github.com/PJLab-ADG/neuralsim.git $NS
```

### 7.2 如果之前未带 submodules

```bash
cd $NS
git submodule update --init --recursive
```

## 8. 创建 `waymo-prep` 环境并安装依赖

```bash
conda create -n waymo-prep python=3.8 -y
conda activate waymo-prep
```

### 8.1 安装 PyTorch 与 torchvision

```bash
conda activate waymo-prep
conda install pytorch torchvision cpuonly -c pytorch -y
```

### 8.2 安装基础 Python 包

```bash
pip install numpy scipy pillow tqdm imageio imagesize scikit-image psutil \
  pyyaml omegaconf addict pyparsing opencv-python-headless
```

### 8.3 安装 Waymo 预处理核心包

```bash
pip install tensorflow==2.11.0 waymo-open-dataset-tf-2-11-0
```

### 8.4 配置 `PYTHONPATH`

在 `waymo-prep` 环境中执行：

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
```

检查：

```bash
python - <<'PY'
import importlib.util
print(importlib.util.find_spec("dataio"))
print(importlib.util.find_spec("nr3d_lib"))
print(importlib.util.find_spec("nr3d_lib.utils"))
PY
```

期望结果：

- 三行均返回 `ModuleSpec(...)`
- 不返回 `None`

### 8.5 验证 `waymo-prep` 环境

#### 8.5.1 验证 Python 导入

```bash
python - <<'PY'
import nr3d_lib.utils
import nr3d_lib.config
import dataio.autonomous_driving.waymo.waymo_dataset
print("python import ok")
PY
```

#### 8.5.2 验证 TensorFlow 与 Waymo 包

```bash
python - <<'PY'
import tensorflow as tf
from waymo_open_dataset import dataset_pb2
import dataio.autonomous_driving.waymo.preprocess as p
print("tf", tf.__version__)
PY
```

期望结果：

- 无异常退出
- 输出 TensorFlow 版本号

## 9. 下载 Waymo 原始数据

### 9.1 下载 NeuralSim 提供的 32 个静态场景

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
cd $NS/dataio/autonomous_driving/waymo
bash download_waymo.sh waymo_static_32.lst $RAW
```

### 9.2 只下载一个场景

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
cd $NS/dataio/autonomous_driving/waymo
printf '%s\n' "$SCENE_ID" > one_scene.lst
bash download_waymo.sh one_scene.lst $RAW
```

### 9.3 下载结果检查

```bash
find $RAW -maxdepth 1 -name '*.tfrecord' | head
find $RAW -maxdepth 1 -name '*.tfrecord' | wc -l
```

## 10. 运行 NeuralSim 预处理

### 10.1 处理 32 个静态场景

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
cd $NS/dataio/autonomous_driving/waymo
python preprocess.py --root=$RAW --out_root=$PROC -j4 --seq_list=waymo_static_32.lst
```

### 10.2 只处理一个场景

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
cd $NS/dataio/autonomous_driving/waymo
python preprocess.py --root=$RAW --out_root=$PROC -j1 --seq_list=one_scene.lst
```

### 10.3 预处理输出结构

```text
$PROC/<scene_id>/
├── images/
│   ├── camera_FRONT/
│   ├── camera_FRONT_LEFT/
│   ├── camera_FRONT_RIGHT/
│   ├── camera_SIDE_LEFT/
│   └── camera_SIDE_RIGHT/
├── lidars/
└── scenario.pt
```

## 11. 转换为 VINGS 数据目录

VINGS 当前 Waymo `vo` 只使用前视相机。

### 11.1 为所有场景创建 VINGS 包装目录

```bash
mkdir -p $VINGS_DATA

for scene_dir in "$PROC"/*; do
  [ -d "$scene_dir" ] || continue
  scene_id=$(basename "$scene_dir")
  mkdir -p "$VINGS_DATA/$scene_id"
  ln -sfn "$scene_dir/images/camera_FRONT" "$VINGS_DATA/$scene_id/color"
done
```

执行后目录结构应为：

```text
$VINGS_DATA/
└── <scene_id>/
    └── color -> $PROC/<scene_id>/images/camera_FRONT
```

### 11.2 复制索引文件

```bash
cp $NS/dataio/autonomous_driving/waymo/waymo_static_32.lst $VINGS_DATA
```

## 12. 运行 VINGS

记得修改配置文件路径：

```bash
python scripts/run.py configs/waymo/Scene01.yaml
```

## 13. 参考位置

- NeuralSim Waymo 说明：[https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/README.md](https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/README.md)
- NeuralSim 下载脚本：[https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/download_waymo.sh](https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/download_waymo.sh)
- NeuralSim 预处理脚本：[https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/preprocess.py](https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/preprocess.py)
- VINGS Waymo loader：[`scripts/datasets/waymo.py`](/home/dzp62442/Projects/VINGS-Mono/scripts/datasets/waymo.py)
- VINGS Waymo 模板：[`configs/waymo/Scene01.yaml`](/home/dzp62442/Projects/VINGS-Mono/configs/waymo/Scene01.yaml)
- VINGS 运行入口：[`scripts/run.py`](/home/dzp62442/Projects/VINGS-Mono/scripts/run.py)
