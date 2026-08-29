from pathlib import Path
import numpy as np

for path in sorted(Path('dump_fp32').glob('*.npy')):
    data = np.load(path)

    print(
        f'{path.name:30s}',
        f'shape={str(data.shape):20s}',
        f'min={data.min():12.6f}',
        f'max={data.max():12.6f}',
        f'max_abs={np.abs(data).max():12.6f}'
    )