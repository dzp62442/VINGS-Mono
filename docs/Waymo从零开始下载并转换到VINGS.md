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

1. 接受 Waymo 数据协议：<https://waymo.com/open/>
2. 安装 `gcloud` 与 `gsutil`
3. 执行 Google 登录：

```bash
gcloud auth login
```

## 6. 目录规划
建议使用以下路径：

```bash
export NS=/path/to/neuralsim
export RAW=/data/waymo/raw
export PROC=/data/waymo/processed
export VINGS_DATA=/data/vings/waymo/scene01
export SCENE_ID=segment-1172406780360799916_1660_000_1680_000_with_camera_labels
```

说明：
- `NS`：NeuralSim 根目录
- `RAW`：Waymo 原始 `.tfrecord` 目录
- `PROC`：NeuralSim 预处理输出目录
- `VINGS_DATA`：VINGS 最终读取目录
- `SCENE_ID`：单个 Waymo 场景名

建议：
- `RAW` 放大容量磁盘
- `PROC` 放 SSD
- `VINGS_DATA` 优先使用软链接方式构建

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

### 7.3 检查 `nr3d_lib`

```bash
find $NS/nr3d_lib -maxdepth 2 -type f | head
```

至少应包含：
- `$NS/nr3d_lib/setup.py`
- `$NS/nr3d_lib/nr3d_lib/utils.py`
- `$NS/nr3d_lib/nr3d_lib/config.py`

## 8. 创建 `waymo-prep` 环境

```bash
conda create -n waymo-prep python=3.8 -y
conda activate waymo-prep
```

## 9. 安装 `waymo-prep` 依赖
### 9.1 安装 PyTorch 与 torchvision

```bash
conda activate waymo-prep
conda install pytorch torchvision cpuonly -c pytorch -y
```

### 9.2 安装基础 Python 包

```bash
pip install numpy scipy pillow tqdm imageio imagesize scikit-image psutil \
  pyyaml omegaconf addict pyparsing opencv-python-headless
```

### 9.3 安装 Waymo 预处理核心包

```bash
pip install tensorflow==2.11.0 waymo-open-dataset-tf-2-11-0
```

## 10. 配置 `PYTHONPATH`
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

## 11. 验证 `waymo-prep` 环境
### 11.1 验证 Python 导入

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
python - <<'PY'
import nr3d_lib.utils
import nr3d_lib.config
import dataio.autonomous_driving.waymo.waymo_dataset
print("python import ok")
PY
```

### 11.2 验证 TensorFlow 与 Waymo 包

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
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

## 12. 下载 Waymo 原始数据
### 12.1 下载 NeuralSim 提供的 32 个静态场景

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
cd $NS/dataio/autonomous_driving/waymo
bash download_waymo.sh waymo_static_32.lst $RAW
```

### 12.2 只下载一个场景

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
cd $NS/dataio/autonomous_driving/waymo
printf '%s\n' "$SCENE_ID" > one_scene.lst
bash download_waymo.sh one_scene.lst $RAW
```

### 12.3 下载结果检查

```bash
find $RAW -maxdepth 1 -name '*.tfrecord' | head
find $RAW -maxdepth 1 -name '*.tfrecord' | wc -l
```

## 13. 运行 NeuralSim 预处理
### 13.1 处理 32 个静态场景

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
cd $NS/dataio/autonomous_driving/waymo
python preprocess.py --root=$RAW --out_root=$PROC -j4 --seq_list=waymo_static_32.lst
```

### 13.2 只处理一个场景

```bash
conda activate waymo-prep
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
cd $NS/dataio/autonomous_driving/waymo
python preprocess.py --root=$RAW --out_root=$PROC -j1 --seq_list=one_scene.lst
```

建议：
- 先使用 `-j1`
- 单场景跑通后再尝试更高并行度

### 13.3 预处理输出结构

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

### 13.4 输出检查

```bash
find $PROC/$SCENE_ID/images/camera_FRONT -maxdepth 1 -type f | head
find $PROC/$SCENE_ID/images/camera_FRONT -maxdepth 1 -type f | wc -l
```

## 14. 转换为 VINGS 数据目录
VINGS 当前 Waymo `vo` 只使用前视相机。

### 14.1 使用软链接

```bash
mkdir -p $VINGS_DATA
ln -s $PROC/$SCENE_ID/images/camera_FRONT $VINGS_DATA/color
```

### 14.2 使用复制

```bash
mkdir -p $VINGS_DATA/color
cp -r $PROC/$SCENE_ID/images/camera_FRONT/* $VINGS_DATA/color/
```

### 14.3 检查结果

```bash
find $VINGS_DATA/color -maxdepth 1 -type f | head
find $VINGS_DATA/color -maxdepth 1 -type f | wc -l
```

目标目录：

```text
$VINGS_DATA/
└── color/
    ├── 00000000.jpg
    ├── 00000001.jpg
    └── ...
```

## 15. 配置 VINGS
### 15.1 复制 Waymo 模板

```bash
cp configs/waymo/Scene01.yaml configs/waymo/my_waymo_vo.yaml
```

### 15.2 修改关键字段

```yaml
mode: 'vo'
use_metric: False
dataset:
  root: /path/to/VINGS_Waymo/scene01
  module: datasets.waymo
output:
  save_dir: /path/to/VINGS_output
frontend:
  weight: /path/to/VINGS-Mono/ckpts/droid.pth
```

### 15.3 保留或写入内参

```yaml
intrinsic:
  fu: 2044.508
  fv: 2044.508
  cu: 633.2422
  cv: 979.5746
  H: 1280
  W: 1920
```

## 16. 补齐 `looper` 配置
在 `configs/waymo/my_waymo_vo.yaml` 中保留以下字段：

```yaml
use_loop: False
looper:
  lightglue_weight_dir: /path/to/VINGS-Mono/ckpts/lightglue
  onnx_w: 512
  H: 344
  W: 616
  loop_radius: 15
  is_loop_min_match_num: 45
  search_num: 30
  is_loop_mse_threshold: 0.15
  is_loop_med_times: 100.0
```

检查文件：

```text
ckpts/lightglue/superpoint.onnx
ckpts/lightglue/superpoint_lightglue.onnx
```

## 17. 运行 VINGS

```bash
python scripts/run.py configs/waymo/my_waymo_vo.yaml
```

## 18. 检查项
### 18.1 检查数据目录

```bash
find $VINGS_DATA/color -maxdepth 1 -type f | head
find $VINGS_DATA/color -maxdepth 1 -type f | wc -l
```

### 18.2 检查配置关键字段

```bash
grep -n "module:\\|root:\\|weight:\\|lightglue_weight_dir" configs/waymo/my_waymo_vo.yaml
```

## 19. 故障处理
### 19.1 `nr3d_lib.utils` 无法导入

执行：

```bash
export PYTHONPATH="$NS:$NS/nr3d_lib:$PYTHONPATH"
```

重新验证第 10 节和第 11 节。

### 19.2 TensorFlow 与 Waymo 包无法导入
重新安装：

```bash
pip install tensorflow==2.11.0 waymo-open-dataset-tf-2-11-0
```

### 19.3 TensorFlow 2.11 路线失败
切换到兼容路线：

```bash
pip uninstall -y tensorflow waymo-open-dataset-tf-2-11-0
pip install tensorflow==2.6.0 waymo-open-dataset-tf-2-6-0 protobuf==3.20.*
```

### 19.4 `preprocess.py` 运行失败
检查以下项目：
- `RAW` 目录中是否存在 `.tfrecord`
- `SCENE_ID` 是否正确
- 是否已完成第 11 节验证
- 并行度是否过高

建议先改为：

```bash
python preprocess.py --root=$RAW --out_root=$PROC -j1 --seq_list=one_scene.lst
```

### 19.5 VINGS 启动时报回环相关错误
检查：
- 配置中是否存在 `looper`
- `ckpts/lightglue/` 下是否存在 ONNX 权重

## 20. 不在本手册范围内
- NeuralSim 街景重建训练
- LiDAR 训练与渲染
- 单目深度提取
- 法线提取
- 语义 mask 提取
- Waymo 多相机联合建图
- Waymo IMU / VIO

## 21. 参考位置
- NeuralSim Waymo 说明：<https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/README.md>
- NeuralSim 下载脚本：<https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/download_waymo.sh>
- NeuralSim 预处理脚本：<https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/preprocess.py>
- VINGS Waymo loader：[`scripts/datasets/waymo.py`](/home/dzp62442/Projects/VINGS-Mono/scripts/datasets/waymo.py)
- VINGS Waymo 模板：[`configs/waymo/Scene01.yaml`](/home/dzp62442/Projects/VINGS-Mono/configs/waymo/Scene01.yaml)
- VINGS 运行入口：[`scripts/run.py`](/home/dzp62442/Projects/VINGS-Mono/scripts/run.py)
