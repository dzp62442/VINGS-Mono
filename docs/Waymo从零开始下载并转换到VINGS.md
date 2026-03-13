# Waymo 下载与转换操作手册

## 1. 适用范围
- 数据集：Waymo Open Dataset Perception v1.x training split
- 场景：室外驾驶
- VINGS 模式：`vo`
- 目标：从 Waymo 原始 `.tfrecord` 生成 VINGS 可直接读取的 `color/*.jpg`
- 约束：只使用 VINGS 与 NeuralSim 现有内容，不新增独立处理脚本

## 2. 环境划分
本流程使用两套环境：

| 环境 | 用途 | 是否需要 NeuralSim |
| --- | --- | --- |
| `vings` | 运行 VINGS | 否 |
| `waymo-prep` | 下载 Waymo、运行 NeuralSim 预处理 | 是 |

要求：
- 不要把 Waymo 预处理依赖装进 `vings`
- 不要把 VINGS 运行依赖装进 `waymo-prep`

## 3. VINGS 最终需要的目录
VINGS 当前 Waymo loader 只读取 `color/*.jpg`，见 [`scripts/datasets/waymo.py`](/home/dzp62442/Projects/VINGS-Mono/scripts/datasets/waymo.py)。

```text
<dataset.root>/
└── color/
    ├── 00000000.jpg
    ├── 00000001.jpg
    └── ...
```

当前 `vo` 主流程不依赖：
- Waymo IMU
- NeuralSim `lidars/`
- NeuralSim `scenario.pt`
- `pose/*.txt`
- 单目深度、法线、语义 mask

## 4. 前置条件
1. 接受 Waymo 数据协议：<https://waymo.com/open/>
2. 安装 `gcloud` 与 `gsutil`
3. 完成登录：

```bash
gcloud auth login
```

## 5. 目录变量
建议先统一路径变量：

```bash
export NS=/path/to/neuralsim
export RAW=/path/to/waymo/training
export PROC=/path/to/waymo/processed
export VINGS_DATA=/path/to/VINGS_Waymo/scene01
export SCENE_ID=segment-1172406780360799916_1660_000_1680_000_with_camera_labels
```

含义：
- `NS`：NeuralSim 仓库根目录
- `RAW`：Waymo 原始 `.tfrecord` 存放目录
- `PROC`：NeuralSim 预处理输出目录
- `VINGS_DATA`：VINGS 最终读取的数据目录
- `SCENE_ID`：单个 Waymo 场景名

## 6. 获取 NeuralSim
克隆仓库并带上 submodules：

```bash
git clone --recursive https://github.com/PJLab-ADG/neuralsim.git $NS
```

如果之前没有带 `--recursive`：

```bash
cd $NS
git submodule update --init --recursive
```

说明：
- NeuralSim 的 Waymo 预处理会导入仓库内代码和 `nr3d_lib`
- 只克隆主仓库但不初始化 submodules，后续导入会失败

## 7. 创建独立的 `waymo-prep` 环境
推荐使用独立 conda 环境：

```bash
conda create -n waymo-prep python=3.8 -y
conda activate waymo-prep
```

说明：
- NeuralSim 官方备份环境使用 `python=3.8`
- 这里不复现 NeuralSim 全量训练环境，只安装 Waymo 预处理实际需要的包
- `Ubuntu 22.04 + RTX 4090` 可以使用这套流程；4090 不是阻塞点

## 8. 安装 `waymo-prep` 必要依赖
### 8.1 安装 PyTorch 基础包
NeuralSim 的部分基础模块会导入 `torch` 和 `torchvision`。Waymo 预处理本身不依赖 PyTorch GPU 计算，CPU 版即可满足导入需求。

```bash
conda activate waymo-prep
conda install pytorch torchvision torchaudio cpuonly -c pytorch -y
```

### 8.2 安装 Python 基础包
这些包来自 `preprocess.py`、`waymo_dataset.py`、`nr3d_lib` 的直接导入需求：

```bash
pip install numpy scipy pillow tqdm imageio imagesize scikit-image psutil \
  pyyaml omegaconf addict pyparsing opencv-python-headless
```

### 8.3 安装 Waymo 预处理核心包
NeuralSim README 里写的是 `tensorflow_gpu==2.11.0`，但当前应优先使用 `tensorflow==2.11.0`：

```bash
pip install tensorflow==2.11.0 waymo-open-dataset-tf-2-11-0
```

### 8.4 启用 NeuralSim Python 路径

```bash
cd $NS
source set_env.sh
```

`set_env.sh` 的作用是把 NeuralSim 仓库根目录加入 `PYTHONPATH`，使 `dataio/...` 与 submodule `nr3d_lib` 可以直接导入。

## 9. 验证 `waymo-prep` 环境
执行以下检查：

```bash
conda activate waymo-prep
cd $NS
source set_env.sh
python -c "import tensorflow as tf; from waymo_open_dataset import dataset_pb2; import dataio.autonomous_driving.waymo.preprocess as p; print('tf', tf.__version__)"
```

期望结果：
- 无报错退出
- 输出 TensorFlow 版本号

如果这里失败，不要继续下载或预处理。

## 10. 下载 Waymo 原始数据
### 10.1 下载 NeuralSim 提供的 32 个静态场景

```bash
conda activate waymo-prep
cd $NS/dataio/autonomous_driving/waymo
bash download_waymo.sh waymo_static_32.lst $RAW
```

### 10.2 只下载一个场景

```bash
conda activate waymo-prep
cd $NS/dataio/autonomous_driving/waymo
printf '%s\n' "$SCENE_ID" > one_scene.lst
bash download_waymo.sh one_scene.lst $RAW
```

### 10.3 下载结果检查

```bash
find $RAW -maxdepth 1 -name '*.tfrecord' | head
find $RAW -maxdepth 1 -name '*.tfrecord' | wc -l
```

目录示例：

```text
$RAW/
├── segment-xxxx.tfrecord
├── segment-yyyy.tfrecord
└── ...
```

## 11. 运行 NeuralSim 预处理
### 11.1 处理 32 个静态场景

```bash
conda activate waymo-prep
cd $NS
source set_env.sh
cd dataio/autonomous_driving/waymo
python preprocess.py --root=$RAW --out_root=$PROC -j4 --seq_list=waymo_static_32.lst
```

### 11.2 只处理一个场景

```bash
conda activate waymo-prep
cd $NS
source set_env.sh
cd dataio/autonomous_driving/waymo
python preprocess.py --root=$RAW --out_root=$PROC -j1 --seq_list=one_scene.lst
```

说明：
- 优先从 `-j1` 开始，确认单场景能跑通后再提高并行度
- 数据在移动硬盘上时，较高并行度更容易卡住

### 11.3 预处理输出结构

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

## 12. 转成 VINGS 可读目录
VINGS 当前 Waymo `vo` 流程只读取前视相机图像，因此只需要把 `camera_FRONT` 映射为 `color`。

### 12.1 使用软链接

```bash
mkdir -p $VINGS_DATA
ln -s $PROC/$SCENE_ID/images/camera_FRONT $VINGS_DATA/color
```

### 12.2 使用复制

```bash
mkdir -p $VINGS_DATA/color
cp -r $PROC/$SCENE_ID/images/camera_FRONT/* $VINGS_DATA/color/
```

### 12.3 结果检查

```bash
find $VINGS_DATA/color -maxdepth 1 -type f | head
find $VINGS_DATA/color -maxdepth 1 -type f | wc -l
```

目标目录应为：

```text
$VINGS_DATA/
└── color/
    ├── 00000000.jpg
    ├── 00000001.jpg
    └── ...
```

## 13. 准备 VINGS 配置文件
复制模板：

```bash
cp configs/waymo/Scene01.yaml configs/waymo/my_waymo_vo.yaml
```

修改以下字段：

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

保留或写入以下内参：

```yaml
intrinsic:
  fu: 2044.508
  fv: 2044.508
  cu: 633.2422
  cv: 979.5746
  H: 1280
  W: 1920
```

## 14. 补齐 `looper` 配置
当前仓库的 `scripts/run.py` 会初始化 `LoopModel`。即使关闭回环，也保留以下字段：

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

同时检查以下文件存在：

```text
ckpts/lightglue/superpoint.onnx
ckpts/lightglue/superpoint_lightglue.onnx
```

## 15. 运行 VINGS

```bash
python scripts/run.py configs/waymo/my_waymo_vo.yaml
```

## 16. 检查项
### 16.1 检查数据目录

```bash
find $VINGS_DATA/color -maxdepth 1 -type f | head
find $VINGS_DATA/color -maxdepth 1 -type f | wc -l
```

### 16.2 检查配置关键字段

```bash
grep -n "module:\\|root:\\|weight:\\|lightglue_weight_dir" configs/waymo/my_waymo_vo.yaml
```

## 17. 故障处理
### 17.1 `download_waymo.sh` 失败
- 未接受 Waymo 协议
- 未执行 `gcloud auth login`
- `gsutil` 未安装

### 17.2 `python -c "import ... preprocess"` 失败
- 未执行 `git submodule update --init --recursive`
- 未执行 `source set_env.sh`
- 缺少 `torch`、`torchvision`
- 缺少 `omegaconf`、`addict`、`imagesize`、`scikit-image` 等基础包

### 17.3 `preprocess.py` 失败
- 未安装 `tensorflow==2.11.0`
- 未安装 `waymo-open-dataset-tf-2-11-0`
- 并行处理不稳定，改用 `-j1`
- 如果 `2.11.0` 路线失败，可退回 NeuralSim README 提供的兼容路线：

```bash
pip uninstall -y tensorflow waymo-open-dataset-tf-2-11-0
pip install tensorflow==2.6.0 waymo-open-dataset-tf-2-6-0 protobuf==3.20.*
```

### 17.4 VINGS 启动时报回环相关错误
- 配置中缺少 `looper`
- `ckpts/lightglue/` 下缺少 ONNX 权重

## 18. 本流程未覆盖的内容
以下内容不是把 Waymo 跑通到 VINGS `vo` 所必需的，不在本手册范围内：
- NeuralSim 街景重建训练
- LiDAR 训练或渲染
- 单目深度提取
- 法线提取
- 语义 mask 提取
- Waymo 多相机联合使用
- Waymo IMU / VIO

## 19. 参考位置
- NeuralSim Waymo 说明：<https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/README.md>
- NeuralSim 下载脚本：<https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/download_waymo.sh>
- NeuralSim 预处理脚本：<https://github.com/PJLab-ADG/neuralsim/blob/main/dataio/autonomous_driving/waymo/preprocess.py>
- NeuralSim `set_env.sh`：<https://github.com/PJLab-ADG/neuralsim/blob/main/set_env.sh>
- NeuralSim 数据格式说明：<https://github.com/PJLab-ADG/neuralsim/blob/main/docs/data/autonomous_driving.md>
- `nr3d_lib` 安装说明：<https://github.com/PJLab-ADG/nr3d_lib#installation>
- TensorFlow pip 安装说明：<https://www.tensorflow.org/install/pip>
- Waymo TF 2.11 包：<https://pypi.org/project/waymo-open-dataset-tf-2-11-0/>
- VINGS Waymo loader：[`scripts/datasets/waymo.py`](/home/dzp62442/Projects/VINGS-Mono/scripts/datasets/waymo.py)
