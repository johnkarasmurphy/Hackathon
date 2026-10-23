import glob
import os

import pandas as pd
import xarray as xr

SRC_DIR = '2026'
OUT_DIR = '2026_csv'
os.makedirs(OUT_DIR, exist_ok=True)

for path in sorted(glob.glob(os.path.join(SRC_DIR, '*.nc'))):
    out = os.path.join(OUT_DIR, os.path.basename(path).replace('.nc', '.csv'))
    if os.path.exists(out):
        continue

    # 1. Open the NetCDF file
    ds = xr.open_dataset(path)

    # 2. Convert to a pandas DataFrame and reset index
    df = ds[['NDVI', 'TIMEOFDAY', 'QA']].to_dataframe().reset_index()

    # 3. Keep only valid pixels (masked NDVI is ~73% of the grid)
    df = df.dropna(subset=['NDVI'])
    df = df.rename(columns={'time': 'date'})
    df['date'] = pd.to_datetime(df['date']).dt.date

    # 4. Export to CSV (write to .tmp first so a partial file is never mistaken for done)
    df.to_csv(out + '.tmp', index=False)
    os.replace(out + '.tmp', out)
    ds.close()
    print(out, len(df))
