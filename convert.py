import glob
import os
import sys

import pandas as pd
import xarray as xr

YEAR = sys.argv[1] if len(sys.argv) > 1 else '2026'
SRC_DIR = YEAR
OUT_DIR = f'ndvi_{YEAR}_chunks'
os.makedirs(OUT_DIR, exist_ok=True)

# California bounding box
LAT_MAX, LAT_MIN = 42.5, 32.0
LON_MIN, LON_MAX = -124.8, -114.0

# One CSV per month (each well under 250 MB); write to .tmp first so a partial file is never mistaken for done
paths = sorted(glob.glob(os.path.join(SRC_DIR, '*.nc')))
months = sorted({os.path.basename(p).split('_')[4][:6] for p in paths})
total = 0
for month in months:
    out = os.path.join(OUT_DIR, f'ndvi_{YEAR}_{month[:4]}-{month[4:]}.csv')
    if os.path.exists(out):
        continue
    tmp = out + '.tmp'
    if os.path.exists(tmp):
        os.remove(tmp)
    first = True
    n_month = 0
    for path in (p for p in paths if os.path.basename(p).split('_')[4][:6] == month):
        # 1. Open the NetCDF file
        ds = xr.open_dataset(path)

        # 2. Slice the California box (latitude is stored north to south)
        try:
            ds = ds.sel(latitude=slice(LAT_MAX, LAT_MIN), longitude=slice(LON_MIN, LON_MAX))
        except KeyError:
            ds = None
        if ds is None or ds.sizes['latitude'] == 0 or ds.sizes['longitude'] == 0:
            print('skipped (bad coordinates or no pixels in box):', path)
            continue

        # 3. Convert to a pandas DataFrame and reset index
        df = ds[['NDVI', 'TIMEOFDAY', 'QA']].to_dataframe().reset_index()

        # 4. Keep only valid pixels (about 70% of the California box is valid)
        df = df.dropna(subset=['NDVI'])
        df = df.rename(columns={'time': 'date'})
        df['date'] = pd.to_datetime(df['date']).dt.date

        # 5. Append to the month's CSV
        df.to_csv(tmp, mode='a', header=first, index=False)
        first = False
        n_month += len(df)
        ds.close()
        print(path, len(df))

    os.replace(tmp, out)
    total += n_month
    print(out, n_month)
print(OUT_DIR, total)
