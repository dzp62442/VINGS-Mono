conda create --name vings_vio python=3.9.19
conda activate vings_vio
pip install torch==2.0.1 torchvision==0.15.2 torchaudio==2.0.2 --index-url https://download.pytorch.org/whl/cu118
pip install torch-scatter==2.0.2 -f https://data.pyg.org/whl/torch-2.0.2+cu118.html --no-build-isolation
pip install -r requirements.txt --no-build-isolation

# Build dbaf.
cd submodules/dbaf
python setup.py install
