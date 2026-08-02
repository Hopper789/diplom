# User Task Template

`user_task.py` must define `run(params)`.

Each line in `params.jsonl` is one independent BOINC workunit. The JSON object
from that line is passed to `run(params)`.

Run the template:

```bash
./scripts/run_experiment.sh --task user --submit-only
```

Run your own task:

```bash
./scripts/run_experiment.sh \
  --task user \
  --user-task path/to/user_task.py \
  --user-params path/to/params.jsonl
```

## External dataset

Do not put large datasets into `params.jsonl`. Keep JSONL for small parameters
and pass datasets as BOINC input files:

```bash
apps/python_task_runner/run_task.sh \
  --task path/to/user_task.py \
  --params path/to/params.jsonl \
  --extra-input data/train.csv:train.csv
```

Then read `train.csv` from `run(params)`:

```python
import numpy as np

def run(params):
    data = np.loadtxt("train.csv", delimiter=",", skiprows=1)
    return {"rows": int(data.shape[0])}
```
